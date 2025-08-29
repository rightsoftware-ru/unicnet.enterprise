#!/usr/bin/env bash
# Interactive installer for UnicNet Enterprise (v11.1, resilient + uninstall/reinstall + safe passwords)
# Date: 2025-08-29

set -Euo pipefail

# =========================
# Config / Defaults
# =========================
REPO_URL="${REPO_URL:-https://github.com/rightsoftware-ru/unicnet.enterprise.git}"
REPO_DIR="${REPO_DIR:-unicnet.enterprise}"
COMPOSE_FILE="${COMPOSE_FILE:-app/unicnet_all_in_one.yml}"
ENV_FILE="${ENV_FILE:-app/.env}"
REALM_JSON_SRC="${REALM_JSON_SRC:-app/unicnet-realm.json}"
REALM_JSON_TMP="${REALM_JSON_TMP:-/tmp/unicnet-realm.resolved.json}"
DOCKER_NETWORK="${DOCKER_NETWORK:-unicnet_network}"
CONFIG_FILE="${CONFIG_FILE:-.unicnet_installer.conf}"

# Match project defaults
BASE_USER_DEFAULT="${BASE_USER_DEFAULT:-unicnet}"
BASE_PASS_DEFAULT="${BASE_PASS_DEFAULT:-unicnet}"
REALM_DEFAULT="${REALM_DEFAULT:-unicnet}"
KC_PORT_DEFAULT="${KC_PORT_DEFAULT:-8095}"
BACK_PORT_DEFAULT="${BACK_PORT_DEFAULT:-30111}"
RMQ_PORT_DEFAULT="${RMQ_PORT_DEFAULT:-15672}"
APP_PORT_DEFAULT="${APP_PORT_DEFAULT:-8080}"

# Pre-filled Yandex CR token (can be overwritten at prompt or via env YCR_TOKEN)
YCR_TOKEN_DEFAULT="y0_AgAAAAB3muX6AATuwQAAAAEawLLRAAB9TQHeGyxGPZXkjVDHF1ZNJcV8UQ"

# Absolute paths
SCRIPT_CWD="$(pwd)"
case "$REPO_DIR" in
  /*) REPO_PATH="$REPO_DIR";;
  *)  REPO_PATH="$SCRIPT_CWD/$REPO_DIR";;
esac
compose_file_abs() { echo "${REPO_PATH}/${COMPOSE_FILE}"; }
env_file_abs()     { echo "${REPO_PATH}/${ENV_FILE}"; }
realm_src_abs()    { echo "${REPO_PATH}/${REALM_JSON_SRC}"; }

# Runtime vars
SERVER_IP=""
YCR_TOKEN="${YCR_TOKEN:-$YCR_TOKEN_DEFAULT}"
REALM="${REALM_DEFAULT}"
KC_ADMIN="${BASE_USER_DEFAULT}"
KC_PASS="${BASE_PASS_DEFAULT}"
NEW_USER="unicadmin"
NEW_USER_PASS=""
NEW_USER_EMAIL="unicadmin@local"
ASSIGNED_GROUPS=""
KC_PORT=""
KC_URL=""
KC_SCHEME="http"
CURL_OPTS=()
ACCESS_TOKEN=""

# =========================
# UI helpers
# =========================
GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; BLUE="\033[1;34m"; GRAY="\033[0;90m"; NC="\033[0m"
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }
info() { echo -e "${BLUE}[*]${NC} $*"; }
sep()  { echo -e "${GRAY}----------------------------------------------------------------${NC}"; }
pause() { read -rp "Нажмите Enter, чтобы продолжить..."; }

# =========================
# Helpers
# =========================
need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Нужна команда: $1"; return 1; }; }

is_valid_ipv4() {
  local ip="$1" IFS='.'; read -r -a o <<< "$ip"
  [[ ${#o[@]} -eq 4 ]] || return 1
  for part in "${o[@]}"; do
    [[ "$part" =~ ^[0-9]+$ ]] || return 1
    (( part >= 0 && part <= 255 )) || return 1
  done
  return 0
}

ask_yes_no() { # ask_yes_no "Вопрос?" "N"
  local prompt="$1" default="${2:-N}" ans
  read -rp "$prompt [y/N]: " ans || true
  ans="${ans:-$default}"
  case "$ans" in y|Y) return 0 ;; *) return 1 ;; esac
}
confirm_nuke() {
  echo
  warn "ЭТО УДАЛИТ контейнеры, тома, сеть, локальный репозиторий, конфиг установщика."
  read -rp "Для подтверждения наберите: DELETE → " ans || true
  [[ "${ans:-}" == "DELETE" ]]
}

_esc_squote() { printf %s "$1" | sed "s/'/'\\''/g"; }
write_config() {
  umask 077
  local f="$SCRIPT_CWD/$CONFIG_FILE"
  mv -f "$f" "$f.bak" 2>/dev/null || true
  cat >"$f" <<EOF
# Автосохранённые ответы установщика UnicNet (создано: $(date -Iseconds))
SERVER_IP='$( _esc_squote "$SERVER_IP" )'
REALM='$( _esc_squote "$REALM" )'
KC_ADMIN='$( _esc_squote "$KC_ADMIN" )'
KC_PASS='$( _esc_squote "$KC_PASS" )'
NEW_USER='$( _esc_squote "$NEW_USER" )'
NEW_USER_PASS='$( _esc_squote "$NEW_USER_PASS" )'
NEW_USER_EMAIL='$( _esc_squote "$NEW_USER_EMAIL" )'
YCR_TOKEN='$( _esc_squote "${YCR_TOKEN}" )'
EOF
}
load_config_if_exists() {
  local f="$SCRIPT_CWD/$CONFIG_FILE"
  if [ -f "$f" ]; then
    # shellcheck disable=SC1090
    . "$f"
    info "Найдены сохранённые параметры → использую $CONFIG_FILE без повторных вопросов."
    return 0
  fi
  return 1
}

ask_with_default() {
  local var="$1" prompt="$2" default="${3:-}"
  local input
  if [ -n "$default" ]; then
    read -rp "$prompt [$default]: " input || true
    input="${input:-$default}"
  else
    read -rp "$prompt: " input || true
  fi
  printf -v "$var" "%s" "$input"
}

ask_secret() {
  local var="$1" prompt="$2" default_set="${3:-}"
  local input
  if [ -n "$default_set" ]; then
    read -rsp "$prompt [Enter — оставить сохранённый]: " input || true; echo
    input="${input:-$default_set}"
  else
    read -rsp "$prompt: " input || true; echo
  fi
  printf -v "$var" "%s" "$input"
}

rand_pass() {
  LC_ALL=C tr -dc 'A-Za-z0-9!@#%+=_-' </dev/urandom | head -c 20
}

curl_http_code() {
  # echo only http code; uses global CURL_OPTS
  curl -s "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 20 "$@"
}

http_ok() {
  local url="$1" code
  code="$(curl_http_code "$url" || echo 000)"
  case "$code" in 2*|3*) return 0 ;; *) return 1 ;; esac
}

wait_kc_ready() {
  local base="$1" tries="${2:-60}" sleep_s="${3:-5}"
  local urls=(
    "$base/health/ready"
    "$base/q/health/ready"
    "$base/realms/master/.well-known/openid-configuration"
    "$base/realms/master"
    "$base/"
  )
  local i=0
  while (( i < tries )); do
    for u in "${urls[@]}"; do http_ok "$u" && return 0; done
    printf "."; sleep "$sleep_s"; i=$((i+1))
  done
  echo
  echo "Диагностика Keycloak readiness (HTTP коды):"
  for u in "${urls[@]}"; do
    local c; c="$(curl_http_code "$u" || echo 000)"
    echo "  $u -> $c"
  done
  return 1
}

ensure_repo() {
  if [ ! -d "$REPO_PATH/.git" ]; then
    log "Репозиторий не найден → клонирую $REPO_URL → $REPO_PATH"
    git clone "$REPO_URL" "$REPO_PATH" || return 1
  fi
}

# KC helpers
kc_get_admin_token() {
  local paths=(
    "/realms/master/protocol/openid-connect/token"
    "/auth/realms/master/protocol/openid-connect/token"
  )
  local p tok
  for p in "${paths[@]}"; do
    tok="$(
      curl -s "${CURL_OPTS[@]}" \
        --connect-timeout 10 --max-time 30 \
        -X POST "${KC_URL}${p}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "username=${KC_ADMIN}" \
        --data-urlencode "password=${KC_PASS}" \
        --data-urlencode "grant_type=password" \
        --data-urlencode "client_id=admin-cli" \
      | jq -r 'try (.access_token) catch empty'
    )"
    if [ -n "$tok" ] && [ "$tok" != "null" ]; then
      echo "$tok"; return 0
    fi
  done
  return 1
}

run_step() {
  local title="$1"; shift
  sep; echo -e "=== $title ==="; sep
  set +e
  "$@"; local rc=$?
  set -e
  if [ $rc -eq 0 ]; then log "Шаг «$title» завершён успешно."
  else err "Шаг «$title» завершился с ошибкой (код $rc)."; fi
  pause
  return $rc
}

# =========================
# Inputs
# =========================
collect_inputs() {
  echo -e "\n$(sep)\n        Мастер установки UnicNet Enterprise (интерактивный)\n$(sep)"
  if load_config_if_exists; then
    info "SERVER_IP = $SERVER_IP"
  else
    while true; do
      ask_with_default SERVER_IP "Внутренний IP сервера" "${SERVER_IP:-}"
      is_valid_ipv4 "$SERVER_IP" && break || err "Некорректный IPv4: $SERVER_IP"
    done
    ask_with_default REALM "Имя Keycloak realm" "$REALM"
    ask_with_default KC_ADMIN "Keycloak admin user" "$KC_ADMIN"
    ask_secret       KC_PASS  "Keycloak admin password" "$KC_PASS"

    ask_with_default NEW_USER       "Создаваемый пользователь realm" "$NEW_USER"
    while true; do
      ask_secret NEW_USER_PASS "Пароль для пользователя ${NEW_USER} (Enter — сгенерировать)" ""
      if [ -z "$NEW_USER_PASS" ]; then NEW_USER_PASS="$(rand_pass)"; info "Пароль сгенерирован автоматически."; fi
      [ -n "$NEW_USER_PASS" ] && break
    done
    ask_with_default NEW_USER_EMAIL "Email пользователя" "$NEW_USER_EMAIL"

    ask_secret YCR_TOKEN "Yandex CR OAuth-токен (Enter — оставить по умолчанию)" "$YCR_TOKEN"
    echo
    info "Репозиторий: $REPO_URL"
    info "Каталог:     $REPO_PATH"
    info "Compose:      $(compose_file_abs)"
    info "ENV файл:     $(env_file_abs)"
    write_config; log "Параметры сохранены в $CONFIG_FILE (права 600)."
  fi
}

# =========================
# Steps
# =========================
step_deps() {
  need_cmd curl || return 1
  need_cmd sed  || return 1
  need_cmd awk  || return 1
  need_cmd grep || return 1
  if ! command -v jq >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      log "Устанавливаю jq"; sudo apt-get update -y && sudo apt-get install -y jq || return 1
    else
      err "Не найден jq и пакетный менеджер apt-get. Установите jq вручную."; return 1
    fi
  fi
  if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      log "Устанавливаю git"; sudo apt-get install -y git || return 1
    else
      err "Не найден git и нет apt-get — установите вручную."; return 1
    fi
  fi
  if ! command -v docker >/dev/null 2>&1; then
    log "Устанавливаю Docker (get.docker.com)"
    curl -fsSL https://get.docker.com | sh || return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      warn "Не найден docker compose v2, ставлю docker-compose-plugin"
      sudo apt-get update -y && sudo apt-get install -y docker-compose-plugin || true
    fi
    docker compose version >/dev/null 2>&1 || { err "docker compose не установлен"; return 1; }
  fi
  log "Зависимости в порядке."; return 0
}

step_clone_repo() {
  if [ ! -d "$REPO_PATH/.git" ]; then
    log "Клонирую $REPO_URL → $REPO_PATH"
    git clone "$REPO_URL" "$REPO_PATH" || return 1
  else
    log "Репозиторий найден, выполняю обновление"
    (cd "$REPO_PATH" && git fetch --all --prune && git pull --ff-only) || return 1
  fi
  (cd "$REPO_PATH" && git rev-parse --short HEAD) || true
  return 0
}

step_create_network() {
  if ! docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
    log "Создаю сеть Docker: $DOCKER_NETWORK"
    docker network create "$DOCKER_NETWORK" || return 1
  else
    info "Сеть $DOCKER_NETWORK уже существует."
  fi
  return 0
}

# ensure KEYCLOAK_ADMIN present in .env before starting containers
_step_env_set_kc_admin_vars() {
  local envf="$1"
  local esc_user; esc_user=$(printf '%s' "$KC_ADMIN" | sed -e 's/[\\&/]/\\&/g')
  local esc_pass; esc_pass=$(printf '%s' "$KC_PASS"  | sed -e 's/[\\&/]/\\&/g')
  if grep -qE '^KEYCLOAK_ADMIN=' "$envf"; then
    sed -i -E "s|^KEYCLOAK_ADMIN=.*$|KEYCLOAK_ADMIN=${esc_user}|" "$envf"
  else
    printf '\nKEYCLOAK_ADMIN=%s\n' "$KC_ADMIN" >> "$envf"
  fi
  if grep -qE '^KEYCLOAK_ADMIN_PASSWORD=' "$envf"; then
    sed -i -E "s|^KEYCLOAK_ADMIN_PASSWORD=.*$|KEYCLOAK_ADMIN_PASSWORD=${esc_pass}|" "$envf"
  else
    printf 'KEYCLOAK_ADMIN_PASSWORD=%s\n' "$KC_PASS" >> "$envf"
  fi
  log "В .env записаны KEYCLOAK_ADMIN/KEYCLOAK_ADMIN_PASSWORD."
}

step_prepare_env() {
  ensure_repo || return 1
  local envf; envf="$(env_file_abs)"
  if [ ! -f "$envf" ]; then err "Не найден $envf. Положите шаблон .env (см. инструкцию)."; return 1; fi

  log "Подставляю IP $SERVER_IP в ключевые параметры $envf"
  sed -i -E "s|^(BACKEND_HOST=).*|\1${SERVER_IP}|" "$envf"
  sed -i -E "s|^(FRONTEND_HOST=).*|\1${SERVER_IP}|" "$envf"
  sed -i -E "s|^(KEYCLOAK_HOST=).*|\1${SERVER_IP}|" "$envf"
  sed -i -E "s|^(RABBITMQ_HOST=).*|\1${SERVER_IP}|" "$envf"

  local before after
  before="$(grep -oE '127\.0\.0\.1' "$envf" | wc -l | tr -d ' ')"
  sed -i -E "s/127\.0\.0\.1/$(printf '%s' "$SERVER_IP" | sed 's/\./\\./g')/g" "$envf"
  after="$(grep -oE "$(printf '%s' "$SERVER_IP" | sed 's/\./\\./g')" "$envf" | wc -l | tr -d ' ')"
  log "Заменено '127.0.0.1' → '${SERVER_IP}' в $envf (совпадений: ${before})."

  _step_env_set_kc_admin_vars "$envf"
  return 0
}

step_docker_login() {
  if [ -z "${YCR_TOKEN:-}" ]; then warn "YCR токен не задан — пропускаю docker login."; return 0; fi
  log "Логин в cr.yandex"; echo "${YCR_TOKEN}" | docker login --username oauth --password-stdin cr.yandex || return 1
  return 0
}

step_compose_up() {
  ensure_repo || return 1
  local cf; cf="$(compose_file_abs)"
  log "Запускаю Docker Compose (${cf})"
  # prefer --wait when available
  if docker compose version >/dev/null 2>&1 && docker compose --help 2>/dev/null | grep -q -- '--wait'; then
    docker compose -f "$cf" up -d --wait || return 1
  else
    docker compose -f "$cf" up -d || return 1
  fi
  echo; docker compose -f "$cf" ps || true
  return 0
}

# v11.1: HTTP имеет приоритет, затем HTTPS; проверяем «живость» URL
step_detect_kc_port() {
  ensure_repo || return 1
  local cf; cf="$(compose_file_abs)"
  local envf; envf="$(env_file_abs)"
  local KC_SVC http_port https_port
  KC_SVC="$(docker compose -f "$cf" ps --services | grep -i keycloak | head -n1 || true)"

  if [ -n "$KC_SVC" ]; then
    http_port="$(docker compose -f "$cf" port "$KC_SVC" 8080 | awk -F: 'NF{print $NF; exit}' || true)"
    https_port="$(docker compose -f "$cf" port "$KC_SVC" 8443 | awk -F: 'NF{print $NF; exit}' || true)"
  fi

  local env_port=""
  if [ -f "$envf" ] && grep -qE '^KEYCLOAK_PORT=' "$envf"; then
    env_port="$(grep -E '^KEYCLOAK_PORT=' "$envf" | tail -1 | cut -d= -f2)"
  fi

  local -a candidates=()
  [ -n "$http_port" ]  && candidates+=("http://${SERVER_IP}:${http_port}")
  [ -n "$https_port" ] && candidates+=("https://${SERVER_IP}:${https_port}")
  [ -n "$env_port" ]   && candidates+=("http://${SERVER_IP}:${env_port}" "https://${SERVER_IP}:${env_port}")
  candidates+=("http://${SERVER_IP}:${KC_PORT_DEFAULT}")

  local picked=""
  for u in "${candidates[@]}"; do
    if http_ok "${u}/realms/master"; then picked="$u"; break; fi
  done
  [ -n "$picked" ] || picked="${candidates[0]}"

  KC_URL="$picked"
  case "$KC_URL" in
    https://*) KC_SCHEME="https"; CURL_OPTS=(--insecure) ;;
    *)         KC_SCHEME="http";  CURL_OPTS=() ;;
  esac

  KC_PORT="${KC_URL##*:}"
  KC_PORT="${KC_PORT%%/*}"

  info "Keycloak URL: ${KC_URL} (детектировано)"
  [ "$KC_SCHEME" = "https" ] && info "HTTPS → curl будет использовать --insecure"
  return 0
}

step_wait_keycloak() {
  [ -n "${KC_URL:-}" ] || step_detect_kc_port
  log "Жду готовности Keycloak на ${KC_URL}"
  wait_kc_ready "${KC_URL}" 60 5 || { err "Keycloak не поднялся на ${KC_URL} по ожидаемым эндпоинтам"; return 1; }
  echo; return 0
}

step_import_realm() {
  ensure_repo || return 1
  local realm_src; realm_src="$(realm_src_abs)"
  [ -f "$realm_src" ] || { err "Не найден ${realm_src}"; return 1; }
  cp -f "$realm_src" "${REALM_JSON_TMP}" || return 1
  sed -i "s/internal_IP/${SERVER_IP}/g" "${REALM_JSON_TMP}"

  local JSON_REALM
  JSON_REALM=$(jq -r 'try (.realm) catch empty' "${REALM_JSON_TMP}" || true)
  if [ -n "$JSON_REALM" ] && [ "$REALM" = "$REALM_DEFAULT" ]; then
    REALM="$JSON_REALM"; info "Realm взят из JSON: ${REALM}"
  fi

  [ -n "${KC_URL:-}" ] || step_detect_kc_port
  log "Получаю admin token Keycloak"
  ACCESS_TOKEN="$(kc_get_admin_token || true)"
  if [ -z "$ACCESS_TOKEN" ]; then
    err "Не удалось получить admin token. Проверьте:"
    echo "  • Доступность ${KC_URL}"
    echo "  • Значения KEYCLOAK_ADMIN/KEYCLOAK_ADMIN_PASSWORD (они проставлены в ${ENV_FILE})"
    echo "  • Если в образе используется старый путь /auth/* — он учитывается авто-детектором"
    return 1
  fi

  log "Импортирую realm из JSON"
  local HTTP_CODE
  HTTP_CODE="$(curl -s "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" -X POST "${KC_URL}/admin/realms" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" \
    --data-binary @"${REALM_JSON_TMP}")"
  case "$HTTP_CODE" in
    201) log "Realm '${REALM}' создан." ;;
    409) warn "Realm '${REALM}' уже существует — пропускаю создание." ;;
    *)   err "Ошибка создания realm, HTTP ${HTTP_CODE}"; return 1 ;;
  esac
  return 0
}

step_create_user_and_groups() {
  ensure_repo || return 1
  [ -n "${ACCESS_TOKEN:-}" ] || { err "Нет ACCESS_TOKEN — выполните шаг импорта realm."; return 1; }

  log "Создаю пользователя '${NEW_USER}' в realm '${REALM}'"
  local create_resp_headers user_id httpc
  create_resp_headers="$(mktemp)"
  httpc="$(curl -s "${CURL_OPTS[@]}" -D "${create_resp_headers}" -o /dev/null -w "%{http_code}" \
    -X POST "${KC_URL}/admin/realms/${REALM}/users" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" \
    -d "$(jq -n --arg u "$NEW_USER" --arg e "$NEW_USER_EMAIL" --arg p "$NEW_USER_PASS" \
          '{username:$u, email:$e, enabled:true, emailVerified:true, credentials:[{type:"password", value:$p, temporary:false}] }' )" )"

  case "$httpc" in
    201)
      user_id="$(awk -F'/users/' '/^Location:/ {print $2}' "${create_resp_headers}" | tr -d '\r\n')"
      ;;
    409|200)
      user_id="$(
        curl -s "${CURL_OPTS[@]}" -H "Authorization: Bearer ${ACCESS_TOKEN}" \
          --get --data-urlencode "username=${NEW_USER}" \
          "${KC_URL}/admin/realms/${REALM}/users" \
        | jq -r 'try (if type=="array" and length>0 then .[0].id // empty else "" end) catch ""'
      )"
      ;;
    *)
      err "Создание пользователя вернуло HTTP ${httpc}";;
  esac

  if [ -z "${user_id:-}" ]; then
    err "Не удалось определить ID пользователя."; return 1
  fi

  local all_groups_json
  all_groups_json="$(curl -s "${CURL_OPTS[@]}" -H "Authorization: Bearer ${ACCESS_TOKEN}" "${KC_URL}/admin/realms/${REALM}/groups")"

  mapfile -t all_names < <(printf '%s' "$all_groups_json" | jq -r 'try (.[].name) catch empty')
  local -a pick_names
  mapfile -t pick_names < <(printf '%s\n' "${all_names[@]}" | grep -E '^unicnet_.*_group$' | head -n 3 || true)
  if [ "${#pick_names[@]}" -lt 3 ]; then
    local need=$((3 - ${#pick_names[@]}))
    local extra; mapfile -t extra < <(printf '%s\n' "${all_names[@]}" | head -n "$((need))")
    pick_names+=("${extra[@]}")
  fi
  mapfile -t pick_names < <(printf '%s\n' "${pick_names[@]}" | awk 'NF{a[$0]++} END{for(k in a) print k}')

  if [ "${#pick_names[@]}" -lt 1 ]; then err "Не найдено ни одной группы для назначения."; return 1; fi

  local assigned=()
  for gname in "${pick_names[@]}"; do
    local gid
    gid="$(printf '%s' "$all_groups_json" | jq -r --arg n "$gname" 'try (.[] | select(.name==$n) | .id) catch empty' | head -1)"
    if [ -n "$gid" ]; then
      log "Добавляю пользователя в группу: $gname"
      curl -s "${CURL_OPTS[@]}" -o /dev/null -X PUT -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KC_URL}/admin/realms/${REALM}/users/${user_id}/groups/${gid}" || true
      assigned+=("$gname")
    else
      warn "Группа '$gname' не найдена."
    fi
  done
  ASSIGNED_GROUPS="$(IFS=,; echo "${assigned[*]}")"
  return 0
}

step_put_client_secret() {
  ensure_repo || return 1
  [ -n "${ACCESS_TOKEN:-}" ] || { err "Нет ACCESS_TOKEN — выполните шаг импорта realm."; return 1; }

  local envf; envf="$(env_file_abs)"
  [ -f "$envf" ] || { err "ENV файл не найден: $envf"; return 1; }

  local client_uuid
  client_uuid="$(
    curl -s "${CURL_OPTS[@]}" -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      --get --data-urlencode "clientId=dotnet-solid-client" \
      "${KC_URL}/admin/realms/${REALM}/clients" \
    | jq -r 'try (if type=="array" and length>0 then .[0].id // empty else "" end) catch ""'
  )"
  [ -n "$client_uuid" ] || { warn "Клиент 'dotnet-solid-client' не найден — пропускаю подстановку секрета."; return 0; }

  local client_secret
  client_secret="$(curl -s "${CURL_OPTS[@]}" -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${KC_URL}/admin/realms/${REALM}/clients/${client_uuid}/client-secret" \
    | jq -r 'try (.value) catch empty')"

  if [ -z "$client_secret" ] || [[ "$client_secret" =~ ^\*+$ ]]; then
    warn "Клиентский секрет скрыт или пуст — генерирую новый через POST."
    client_secret="$(curl -s "${CURL_OPTS[@]}" -X POST -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "${KC_URL}/admin/realms/${REALM}/clients/${client_uuid}/client-secret" \
      | jq -r 'try (.value) catch empty')"
  fi

  [ -n "$client_secret" ] || { err "Не удалось получить client secret после POST."; return 1; }

  local cs_esc; cs_esc=$(printf '%s' "$client_secret" | sed -e 's/[\\\/&]/\\&/g' -e 's/"/\\"/g')
  log "Подставляю UnKc.ClientSecret в ${envf}"
  if grep -qE '^UnKc\.ClientSecret[:=]' "$envf"; then
    sed -i -E "s|^(UnKc\.ClientSecret\s*[:=]\s*).*$|\1\"${cs_esc}\"|" "$envf"
  else
    printf '\nUnKc.ClientSecret: "%s"\n' "$client_secret" >> "$envf"
  fi

  log "Перезапуск backend для подхвата секрета"
  docker compose -f "$(compose_file_abs)" up -d --force-recreate unicnet.backend || true
  return 0
}

step_uninstall_full() {
  local cf imgs=""
  cf="$(compose_file_abs 2>/dev/null || true)"
  if [ -f "${cf}" ]; then
    imgs="$(docker compose -f "$cf" images -q 2>/dev/null | sort -u | tr '\n' ' ')"
  fi
  log "Останавливаю стек и удаляю ресурсы Compose"
  if [ -f "${cf}" ]; then docker compose -f "$cf" down -v --remove-orphans || true; fi
  if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
    log "Удаляю сеть Docker: $DOCKER_NETWORK"; docker network rm "$DOCKER_NETWORK" || true
  fi
  if [ -d "$REPO_PATH" ]; then log "Удаляю каталог репозитория: $REPO_PATH"; rm -rf "$REPO_PATH" || true; fi
  log "Удаляю конфиг установщика и временные файлы"
  rm -f "$SCRIPT_CWD/$CONFIG_FILE" "$REALM_JSON_TMP" || true
  if [ -n "$imgs" ] && ask_yes_no "Удалить docker-образы приложения (их можно будет снова скачать)?" "N"; then
    for i in $imgs; do [ -n "$i" ] && docker rmi -f "$i" || true; done
  fi
  log "Полная деинсталляция завершена."; return 0
}

step_reinstall_full() { step_uninstall_full || true; run_all; }

step_summary() {
  echo; sep
  echo "ГОТОВО ✅ Проверьте доступы:"
  echo "  Приложение:      http://${SERVER_IP}:${APP_PORT_DEFAULT}"
  echo "  Keycloak Admin:  ${KC_ADMIN} / ${KC_PASS}  (${KC_URL:-http://${SERVER_IP}:${KC_PORT:-$KC_PORT_DEFAULT}})"
  echo "  Realm:           ${REALM}"
  echo "  User:            ${NEW_USER} / ${NEW_USER_PASS}"
  echo "  Groups:          ${ASSIGNED_GROUPS:-<не присвоены>}"
  echo "  Backend Swagger: http://${SERVER_IP}:${BACK_PORT_DEFAULT}/swagger/index.html"
  echo "  RabbitMQ:        http://${SERVER_IP}:${RMQ_PORT_DEFAULT}/  (логин/пароль как BASE_USER/BASE_PASS)"
  sep
}

# =========================
# Menu
# =========================
run_all() {
  run_step "1/10 Зависимости (Docker, jq, git, compose)"          step_deps          || true
  run_step "2/10 Клонирование/обновление репозитория"             step_clone_repo    || true
  run_step "3/10 Создание сети Docker"                            step_create_network|| true
  run_step "4/10 Подготовка .env (IP + KC admin vars)"            step_prepare_env   || true
  run_step "5/10 Docker login в Yandex CR (опционально)"          step_docker_login  || true
  run_step "6/10 Запуск Docker Compose"                           step_compose_up    || true
  run_step "7/10 Определение схемы/порта Keycloak (http/https)"   step_detect_kc_port|| true
  run_step "8/10 Ожидание готовности Keycloak"                    step_wait_keycloak || true
  run_step "9/10 Импорт realm и получение токена"                 step_import_realm  || true
  run_step "10/10 Создание пользователя и назначение 3 групп"     step_create_user_and_groups || true
  run_step "Дополнительно: Запись client secret и рестарт backend" step_put_client_secret || true
  step_summary
}

main_menu() {
  while true; do
    echo; sep
    echo "Выберите действие:"
    echo "  0) Выполнить всё по порядку"
    echo "  1) Установить зависимости"
    echo "  2) Клонировать/обновить репозиторий"
    echo "  3) Создать сеть Docker"
    echo "  4) Подготовить .env (подставить IP + KC admin vars)"
    echo "  5) Docker login в Yandex CR"
    echo "  6) Запустить Docker Compose"
    echo "  7) Определить порт/схему Keycloak"
    echo "  8) Дождаться готовности Keycloak"
    echo "  9) Импортировать realm"
    echo " 10) Создать пользователя и назначение 3 групп"
    echo " 11) Записать client secret и перезапустить backend"
    echo " 12) Показать итоги/URL"
    echo " 13) Полная деинсталляция (контейнеры, тома, сеть, repo, конфиги)"
    echo " 14) Полная переустановка (деинсталляция + установка с нуля)"
    echo "  q) Выход"
    sep
    read -rp "Ваш выбор: " choice || true
    case "$choice" in
      0) run_all ;;
      1) run_step "Зависимости"                          step_deps ;;
      2) run_step "Клонирование/обновление репозитория" step_clone_repo ;;
      3) run_step "Создание сети Docker"                 step_create_network ;;
      4) run_step "Подготовка .env"                      step_prepare_env ;;
      5) run_step "Docker login в Yandex CR"             step_docker_login ;;
      6) run_step "Запуск Docker Compose"                step_compose_up ;;
      7) run_step "Определение порта/схемы Keycloak"     step_detect_kc_port ;;
      8) run_step "Ожидание готовности Keycloak"         step_wait_keycloak ;;
      9) run_step "Импорт realm"                         step_import_realm ;;
      10) run_step "Создание пользователя и назначение 3 групп" step_create_user_and_groups ;;
      11) run_step "Запись client secret и рестарт backend" step_put_client_secret ;;
      12) step_summary; pause ;;
      13) if confirm_nuke; then run_step "Полная деинсталляция" step_uninstall_full; else warn "Отменено."; fi ;;
      14) if confirm_nuke; then run_step "Полная переустановка" step_reinstall_full; else warn "Отменено."; fi ;;
      q|Q) echo "Выход."; exit 0 ;;
      *) warn "Некорректный выбор." ;;
    esac
  done
}

# =========================
# Run
# =========================
collect_inputs
main_menu
