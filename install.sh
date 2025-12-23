#!/usr/bin/env bash
# Interactive installer for UnicNet Enterprise (v11.1, resilient + uninstall/reinstall + safe passwords)
# Date: 2025-08-29

set -Euo pipefail

# =========================
# Config / Defaults
# =========================
REPO_URL="${REPO_URL:-https://github.com/rightsoftware-ru/unicnet.enterprise.git}"
REPO_DIR="${REPO_DIR:-unicnet.enterprise}"
COMPOSE_FILE="${COMPOSE_FILE:-app/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-app/.env}"
REALM_JSON_SRC="${REALM_JSON_SRC:-app/keycloak-import/unicnet-realm.json}"
DOCKER_NETWORK="${DOCKER_NETWORK:-unicnet_network}"
CONFIG_FILE="${CONFIG_FILE:-unicnet_installer.conf}"

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Определяем путь к репозиторию: если скрипт внутри репозитория, используем его директорию, иначе $REPO_DIR
if [ -f "${SCRIPT_DIR}/${COMPOSE_FILE}" ] || [ -d "${SCRIPT_DIR}/app" ]; then
  REPO_PATH="$SCRIPT_DIR"
elif [ -f "${SCRIPT_CWD}/${COMPOSE_FILE}" ] || [ -d "${SCRIPT_CWD}/app" ]; then
  REPO_PATH="$SCRIPT_CWD"
else
  case "$REPO_DIR" in
    /*) REPO_PATH="$REPO_DIR";;
    *)  REPO_PATH="$SCRIPT_CWD/$REPO_DIR";;
  esac
fi
compose_file_abs() { echo "${REPO_PATH}/${COMPOSE_FILE}"; }
env_file_abs()     { echo "${REPO_PATH}/${ENV_FILE}"; }
realm_src_abs()    { echo "${REPO_PATH}/${REALM_JSON_SRC}"; }

# Runtime vars
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
VAULT_TOKEN=""

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

# Определяем команду docker compose (поддержка docker compose и docker-compose)
_docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    echo "docker-compose"
  else
    return 1
  fi
}

# Выполняет команду docker compose с автоматическим выбором варианта
docker_compose() {
  local cmd exit_code
  cmd="$(_docker_compose_cmd)" || { err "Не найдена команда docker compose или docker-compose"; return 1; }
  # Подавляем предупреждения о 'deploy' configuration
  $cmd "$@" 2>&1 | grep -v "be ignored. Compose does not support 'deploy' configuration" || true
  exit_code=${PIPESTATUS[0]}
  return $exit_code
}

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

_esc_squote() { printf %s "$1" | sed "s/'/'\\''/g"; }
write_config() {
  umask 077
  local f="$SCRIPT_CWD/$CONFIG_FILE"
  mv -f "$f" "$f.bak" 2>/dev/null || true
  cat >"$f" <<EOF
# Автосохранённые ответы установщика UnicNet (создано: $(date -Iseconds))
REALM='$( _esc_squote "$REALM" )'
# KC_ADMIN и KC_PASS не сохраняем - они всегда читаются из контейнера
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
  local dots=""
  while (( i < tries )); do
    for u in "${urls[@]}"; do 
      if http_ok "$u"; then
        if [ -n "$dots" ]; then
          echo -ne "\r${GREEN}✓${NC} Keycloak готов!${dots//./ }"
          echo
        fi
        return 0
      fi
    done
    dots="${dots}."
    local progress=$((i * 100 / tries))
    echo -ne "\r${BLUE}[*]${NC} Ожидание готовности Keycloak... ${progress}% ${dots}"
    sleep "$sleep_s"
    i=$((i+1))
  done
  echo -ne "\r"
  echo
  err "Keycloak не стал доступен за отведенное время"
  echo "Диагностика Keycloak readiness (HTTP коды):"
  for u in "${urls[@]}"; do
    local c; c="$(curl_http_code "$u" || echo 000)"
    case "$c" in
      2*|3*) echo -e "  ${GREEN}✓${NC} $u -> $c" ;;
      *)     echo -e "  ${RED}✗${NC} $u -> $c" ;;
    esac
  done
  return 1
}

# KC helpers
# Читает переменные окружения Keycloak из контейнера
# Поддерживает альтернативные имена переменных
_get_kc_env() {
  local container_name="unicnet.keycloak"
  local var_name="$1" default="$2"
  
  if docker ps --format '{{.Names}}' | grep -q "^${container_name}$" 2>/dev/null; then
    local value
    # Пробуем найти переменную с указанным именем
    value="$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "${container_name}" 2>/dev/null | grep "^${var_name}=" | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//')"
    
    # Если не нашли и ищем KEYCLOAK_ADMIN_USER, пробуем KEYCLOAK_ADMIN как альтернативу
    if [ -z "$value" ] && [ "$var_name" = "KEYCLOAK_ADMIN_USER" ]; then
      value="$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "${container_name}" 2>/dev/null | grep "^KEYCLOAK_ADMIN=" | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//')"
    fi
    
    echo "${value:-$default}"
  else
    echo "$default"
  fi
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
    info "Используются сохранённые параметры из $CONFIG_FILE"
  else
    # Realm будет автоматически взят из JSON файла при импорте
    REALM="$REALM_DEFAULT"
    info "Realm будет автоматически взят из JSON файла при импорте"
    
    # KC_ADMIN и KC_PASS не запрашиваем - они автоматически читаются из контейнера
    info "Keycloak admin credentials будут автоматически прочитаны из контейнера"

    # Пользователь, пароль и email устанавливаются автоматически
    NEW_USER="unicadmin"
    NEW_USER_PASS="$(rand_pass)"
    NEW_USER_EMAIL="unicadmin@local"
    info "Пользователь: ${NEW_USER}"
    info "Пароль сгенерирован автоматически"
    info "Email: ${NEW_USER_EMAIL}"

    # YCR_TOKEN использует значение по умолчанию
    info "Yandex CR OAuth-токен использует значение по умолчанию"
    echo
    info "Репозиторий: $REPO_URL"
    info "Каталог:     $REPO_PATH"
    info "Compose:      $(compose_file_abs)"
    info "ENV файл:     $(env_file_abs)"
    info "JSON realm использует внутренние адреса контейнеров (не требуется запрос IP)"
    write_config; log "Параметры сохранены в $CONFIG_FILE (права 600)."
  fi
}

# =========================
# Steps
# =========================
# Функции для работы с JSON через jq в Docker контейнере
_jq() {
  docker run --rm -i stedolan/jq:latest "$@"
}

json_get_field() {
  local json field="$2"
  if [ $# -gt 0 ] && [ -n "$1" ]; then
    json="$1"
  else
    json="$(cat)"
  fi
  echo "$json" | _jq -r --arg field "$field" '.[$field] // empty'
}

json_get_access_token() {
  local json
  if [ $# -gt 0 ] && [ -n "$1" ]; then
    json="$1"
  else
    json="$(cat)"
  fi
  echo "$json" | _jq -r '.access_token // empty'
}

json_array_get_names() {
  local json field="${2:-name}"
  if [ $# -gt 0 ] && [ -n "$1" ]; then
    json="$1"
  else
    json="$(cat)"
  fi
  echo "$json" | _jq -r --arg field "$field" '.[] | .[$field] // empty'
}

json_array_find_id_by_name() {
  local json search_name="$2" name_field="${3:-name}" id_field="${4:-id}"
  if [ $# -gt 0 ] && [ -n "$1" ]; then
    json="$1"
  else
    json="$(cat)"
  fi
  echo "$json" | _jq -r --arg name "$search_name" --arg name_field "$name_field" --arg id_field "$id_field" \
    '.[] | select(.[$name_field] == $name) | .[$id_field] // empty' | head -1
}

wait_mongo_ready() {
  local container_name="${1:-unicnet.mongo}" tries="${2:-30}" sleep_s="${3:-2}"
  local i=0
  while (( i < tries )); do
    # Пробуем простую проверку ping без аутентификации
    if docker exec "$container_name" mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
      return 0
    fi
    # Альтернативная проверка: пытаемся подключиться к порту
    if docker exec "$container_name" sh -c "nc -z localhost 27017" >/dev/null 2>&1; then
      sleep 1  # Даем немного времени на полную инициализацию
      return 0
    fi
    printf "."; sleep "$sleep_s"; i=$((i+1))
  done
  echo
  return 1
}

# =========================
# Step 5: Создание пользователей и БД в MongoDB
# =========================
step_create_mongo_users_and_dbs() {
  local container_name="unicnet.mongo"
  
  # Проверяем что контейнер запущен
  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    err "Контейнер MongoDB ${container_name} не запущен"
    return 1
  fi
  
  log "Читаю переменные окружения из работающих контейнеров"
  
  # Функция для чтения переменной окружения из контейнера
  get_container_env() {
    local container="$1" var_name="$2" default="$3"
    local value
    if docker ps --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null; then
      value="$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "${container}" 2>/dev/null | grep "^${var_name}=" | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//')"
    fi
    echo "${value:-$default}"
  }
  
  # Функция для парсинга MongoCS connection string (mongodb://user:pass@host:port/db?...)
  parse_mongocs() {
    local mongocs="$1"
    local field="$2"  # user, pass, или db
    if [ -z "$mongocs" ]; then
      echo ""
      return
    fi
    case "$field" in
      user)
        echo "$mongocs" | sed -n 's|mongodb://\([^:]*\):.*|\1|p'
        ;;
      pass)
        echo "$mongocs" | sed -n 's|mongodb://[^:]*:\([^@]*\)@.*|\1|p'
        ;;
      db)
        echo "$mongocs" | sed -n 's|mongodb://[^/]*/\([^?]*\).*|\1|p'
        ;;
      *)
        echo ""
        ;;
    esac
  }
  
  # Читаем root credentials из контейнера MongoDB
  local MONGO_ROOT_USER MONGO_ROOT_PASS
  MONGO_ROOT_USER="$(get_container_env "${container_name}" MONGO_INITDB_ROOT_USERNAME unicnet)"
  MONGO_ROOT_PASS="$(get_container_env "${container_name}" MONGO_INITDB_ROOT_PASSWORD mongo123)"
  
  # Читаем параметры для unicnet_db из контейнера unicnet.backend (или unicnet.syslog)
  local unicnet_mongocs
  unicnet_mongocs="$(get_container_env "unicnet.backend" MongoCS "" 2>/dev/null || get_container_env "unicnet.syslog" MongoCS "" 2>/dev/null || echo "")"
  local MONGO_UNICNET_USER MONGO_UNICNET_PASS MONGO_UNICNET_DB
  if [ -n "$unicnet_mongocs" ]; then
    MONGO_UNICNET_USER="$(parse_mongocs "$unicnet_mongocs" user)"
    MONGO_UNICNET_PASS="$(parse_mongocs "$unicnet_mongocs" pass)"
    MONGO_UNICNET_DB="$(parse_mongocs "$unicnet_mongocs" db)"
  fi
  # Устанавливаем значения по умолчанию, если не удалось распарсить
  MONGO_UNICNET_USER="${MONGO_UNICNET_USER:-unicnet}"
  MONGO_UNICNET_PASS="${MONGO_UNICNET_PASS:-unicnet_pass_123}"
  MONGO_UNICNET_DB="${MONGO_UNICNET_DB:-unicnet_db}"
  
  # Читаем параметры для logger_db из контейнера unicnet.logger
  local logger_mongocs
  logger_mongocs="$(get_container_env "unicnet.logger" MongoCS "" 2>/dev/null || echo "")"
  local MONGO_LOGGER_USER MONGO_LOGGER_PASS MONGO_LOGGER_DB
  if [ -n "$logger_mongocs" ]; then
    MONGO_LOGGER_USER="$(parse_mongocs "$logger_mongocs" user)"
    MONGO_LOGGER_PASS="$(parse_mongocs "$logger_mongocs" pass)"
    MONGO_LOGGER_DB="$(parse_mongocs "$logger_mongocs" db)"
  fi
  MONGO_LOGGER_USER="${MONGO_LOGGER_USER:-logger_user}"
  MONGO_LOGGER_PASS="${MONGO_LOGGER_PASS:-logger_pass_123}"
  MONGO_LOGGER_DB="${MONGO_LOGGER_DB:-logger_db}"
  
  # Читаем параметры для vault_db из контейнера unicnet.vault
  local vault_mongocs
  vault_mongocs="$(get_container_env "unicnet.vault" MongoCS "" 2>/dev/null || echo "")"
  local MONGO_VAULT_USER MONGO_VAULT_PASS MONGO_VAULT_DB
  if [ -n "$vault_mongocs" ]; then
    MONGO_VAULT_USER="$(parse_mongocs "$vault_mongocs" user)"
    MONGO_VAULT_PASS="$(parse_mongocs "$vault_mongocs" pass)"
    MONGO_VAULT_DB="$(parse_mongocs "$vault_mongocs" db)"
  fi
  MONGO_VAULT_USER="${MONGO_VAULT_USER:-vault_user}"
  MONGO_VAULT_PASS="${MONGO_VAULT_PASS:-vault_pass_123}"
  MONGO_VAULT_DB="${MONGO_VAULT_DB:-vault_db}"
  
  info "Прочитаны параметры из контейнеров:"
  info "  Root: ${MONGO_ROOT_USER}"
  info "  UnicNet: ${MONGO_UNICNET_USER}@${MONGO_UNICNET_DB}"
  info "  Logger: ${MONGO_LOGGER_USER}@${MONGO_LOGGER_DB}"
  info "  Vault: ${MONGO_VAULT_USER}@${MONGO_VAULT_DB}"
  
  log "Жду готовности MongoDB контейнера ${container_name}"
  wait_mongo_ready "$container_name" 30 2 || { err "MongoDB не стал доступен"; return 1; }
  echo
  
  log "Создаю базы данных и пользователей в MongoDB"
  
  # Создаем или обновляем пользователей и БД через MongoDB команды
  create_mongo_user() {
    local db_name="$1" username="$2" password="$3"
    local temp_script
    temp_script="$(mktemp)"
    
    cat > "$temp_script" <<EOF
db = db.getSiblingDB('${db_name}');
var userExists = false;

try {
  var userInfo = db.getUser('${username}');
  if (userInfo) {
    userExists = true;
  }
} catch (e) {
  userExists = false;
}

if (userExists) {
  try {
    db.changeUserPassword('${username}', '${password}');
    var currentUser = db.getUser('${username}');
    if (currentUser && currentUser.roles && currentUser.roles.length > 0) {
      db.revokeRolesFromUser('${username}', currentUser.roles);
    }
    db.grantRolesToUser('${username}', [{ role: 'readWrite', db: '${db_name}' }]);
    print('Обновлен пользователь ${username} для БД ${db_name} (пароль и права обновлены)');
  } catch (e) {
    print('Ошибка при обновлении пользователя ${username}: ' + e.message);
    quit(1);
  }
} else {
  try {
    db.createUser({
      user: '${username}',
      pwd: '${password}',
      roles: [{ role: 'readWrite', db: '${db_name}' }]
    });
    print('Создан пользователь ${username} для БД ${db_name}');
  } catch (e) {
    if (e.code === 51003 || e.message.indexOf('already exists') !== -1) {
      try {
        db.changeUserPassword('${username}', '${password}');
        var currentUser = db.getUser('${username}');
        if (currentUser && currentUser.roles && currentUser.roles.length > 0) {
          db.revokeRolesFromUser('${username}', currentUser.roles);
        }
        db.grantRolesToUser('${username}', [{ role: 'readWrite', db: '${db_name}' }]);
        print('Обновлен пользователь ${username} для БД ${db_name} (пароль и права обновлены)');
      } catch (e2) {
        print('Ошибка при обновлении существующего пользователя ${username}: ' + e2.message);
        quit(1);
      }
    } else {
      print('Ошибка при создании пользователя ${username}: ' + e.message);
      quit(1);
    }
  }
}
EOF
    
    docker cp "$temp_script" "${container_name}:/tmp/create_user_${username}.js" >/dev/null 2>&1 || {
      rm -f "$temp_script"
      err "Не удалось скопировать скрипт для пользователя ${username}"
      return 1
    }
    
    local output exit_code
    output="$(docker exec "${container_name}" mongo admin -u "${MONGO_ROOT_USER}" -p "${MONGO_ROOT_PASS}" --authenticationDatabase admin --quiet /tmp/create_user_${username}.js 2>&1)" || exit_code=$?
    
    docker exec "${container_name}" rm -f "/tmp/create_user_${username}.js" >/dev/null 2>&1 || true
    rm -f "$temp_script"
    
    if [ -n "${exit_code:-}" ] && [ "$exit_code" -ne 0 ]; then
      err "Ошибка при создании/обновлении пользователя ${username} в БД ${db_name}: $output"
      return 1
    else
      if echo "$output" | grep -q "Создан пользователь"; then
        log "$output"
      elif echo "$output" | grep -q "Обновлен пользователь"; then
        log "$output"
      else
        info "$output"
      fi
      return 0
    fi
  }
  
  # Создаем всех пользователей
  create_mongo_user "${MONGO_UNICNET_DB}" "${MONGO_UNICNET_USER}" "${MONGO_UNICNET_PASS}" || true
  create_mongo_user "${MONGO_LOGGER_DB}" "${MONGO_LOGGER_USER}" "${MONGO_LOGGER_PASS}" || true
  create_mongo_user "${MONGO_VAULT_DB}" "${MONGO_VAULT_USER}" "${MONGO_VAULT_PASS}" || true
  
  log "Базы данных и пользователи MongoDB успешно созданы:"
  info "  - ${MONGO_UNICNET_DB} (пользователь: ${MONGO_UNICNET_USER})"
  info "  - ${MONGO_LOGGER_DB} (пользователь: ${MONGO_LOGGER_USER})"
  info "  - ${MONGO_VAULT_DB} (пользователь: ${MONGO_VAULT_USER})"
  
  return 0
}

# =========================
# Step 6: Получение токена Vault
# =========================
step_get_vault_token() {
  local container_name="unicnet.vault"
  local vault_token_id="0f8e160416b94225a73f86ac23b9118b"
  local vault_username="UNFrontV2"
  
  # Проверяем, что контейнер запущен
  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    err "Контейнер Vault ${container_name} не запущен"
    return 1
  fi
  
  local vault_port="80"
  local vault_url="http://localhost:${vault_port}"
  
  # Проверяем доступность curl в контейнере
  if ! docker exec "${container_name}" sh -c "command -v curl >/dev/null 2>&1 || which curl >/dev/null 2>&1" 2>/dev/null; then
    log "curl не найден в контейнере vault, устанавливаю curl..."
    
    local curl_installed=false
    local install_output=""
    
    if docker exec "${container_name}" sh -c "command -v apk >/dev/null 2>&1" 2>/dev/null; then
      log "Обнаружен Alpine Linux, устанавливаю curl через apk..."
      install_output="$(docker exec "${container_name}" sh -c "apk update -q && apk add --no-cache curl" 2>&1)"
      if [ $? -eq 0 ] && docker exec "${container_name}" sh -c "command -v curl >/dev/null 2>&1" 2>/dev/null; then
        curl_installed=true
        log "curl успешно установлен через apk"
      fi
    elif docker exec "${container_name}" sh -c "command -v apt-get >/dev/null 2>&1" 2>/dev/null; then
      log "Обнаружен Debian/Ubuntu, устанавливаю curl через apt-get..."
      install_output="$(docker exec "${container_name}" sh -c "apt-get update -qq && apt-get install -y --no-install-recommends curl" 2>&1)"
      if [ $? -eq 0 ] && docker exec "${container_name}" sh -c "command -v curl >/dev/null 2>&1" 2>/dev/null; then
        curl_installed=true
        log "curl успешно установлен через apt-get"
      fi
    elif docker exec "${container_name}" sh -c "command -v yum >/dev/null 2>&1" 2>/dev/null; then
      log "Обнаружен CentOS/RHEL, устанавливаю curl через yum..."
      install_output="$(docker exec "${container_name}" sh -c "yum install -y curl" 2>&1)"
      if [ $? -eq 0 ] && docker exec "${container_name}" sh -c "command -v curl >/dev/null 2>&1" 2>/dev/null; then
        curl_installed=true
        log "curl успешно установлен через yum"
      fi
    else
      err "Не удалось определить пакетный менеджер для установки curl"
      return 1
    fi
    
    if [ "$curl_installed" = false ]; then
      err "Установка curl в контейнере vault не удалась"
      return 1
    fi
  else
    info "curl уже установлен в контейнере vault"
  fi
  
  local vault_api_url="${vault_url}/api/token/${vault_token_id}?username=${vault_username}"
  
  log "Запрашиваю токен Vault для пользователя: ${vault_username}"
  info "URL: ${vault_api_url}"
  
  local response
  response="$(docker exec "${container_name}" sh -c "curl -s -w '\nHTTP_CODE:%{http_code}' '${vault_api_url}'" 2>&1)" || {
    err "Ошибка выполнения curl запроса в контейнере"
    return 1
  }
  
  local http_code
  http_code="$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2 || echo "")"
  local response_body
  response_body="$(echo "$response" | sed '/HTTP_CODE:/d')"
  
  if [ "$http_code" = "200" ]; then
    local token_extracted
    token_extracted="$(echo "$response_body" | _jq -r '.token // .access_token // .value // . // empty' 2>/dev/null || echo "")"
    
    if [ -z "$token_extracted" ] || [ "$token_extracted" = "null" ] || [ "$token_extracted" = "empty" ]; then
      token_extracted="$(echo "$response_body" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//;s/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n')"
    fi
    
    if [ -n "$token_extracted" ] && [ "$token_extracted" != "null" ] && [ "$token_extracted" != "empty" ]; then
      VAULT_TOKEN="$token_extracted"
      log "Токен Vault успешно получен и сохранен для пользователя ${vault_username}"
      info "Длина токена: ${#VAULT_TOKEN} символов"
      echo
      info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      info "Полученный токен Vault:"
      echo "$VAULT_TOKEN"
      info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo
      return 0
    else
      err "Не удалось извлечь токен из ответа Vault"
      err "Ответ сервера:"
      echo "$response_body" | sed 's/^/  /' | head -10
      return 1
    fi
  else
    err "Ошибка получения токена Vault, HTTP ${http_code:-unknown}"
    if [ -n "$response_body" ]; then
      err "Ответ сервера:"
      echo "$response_body" | sed 's/^/  /' | head -20
    fi
    return 1
  fi
}

# =========================
# Step 7: Создание секрета в Vault
# =========================
step_create_vault_secret() {
  local container_name="unicnet.vault"
  local vault_secret_id="UNFrontV2"
  
  # Проверяем, что контейнер запущен
  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    err "Контейнер Vault ${container_name} не запущен"
    return 1
  fi
  
  # Проверяем наличие токена
  if [ -z "${VAULT_TOKEN:-}" ]; then
    warn "VAULT_TOKEN не установлен, пытаюсь получить токен..."
    step_get_vault_token || {
      err "Не удалось получить токен Vault для создания секрета"
      return 1
    }
  fi
  
  # Получаем данные Keycloak из контейнера
  local kc_admin_user kc_admin_pass kc_realm
  kc_admin_user="$(_get_kc_env KEYCLOAK_ADMIN_USER "${KC_ADMIN:-unicnet}")"
  kc_admin_pass="$(_get_kc_env KEYCLOAK_ADMIN_PASSWORD "${KC_PASS:-admin123}")"
  kc_realm="${REALM:-$(_get_kc_env REALM ${REALM_DEFAULT})}"
  
  info "Используются данные Keycloak:"
  info "  Admin User: ${kc_admin_user}"
  info "  Admin Pass: ********"
  info "  Realm: ${kc_realm}"
  
  # Формируем URL с внутренними именами сервисов и портами Docker сети
  local keycloak_url="http://unicnet.keycloak:8080/"
  local backend_url="http://unicnet.backend:8080/"
  local logger_url="http://unicnet.logger:8080/"
  local syslog_url="http://unicnet.syslog:8080/"
  local router_url="http://unicnet.router:30115/"
  local router_hostport="unicnet.router:30115"
  
  info "Используются внутренние URL (Docker сеть):"
  info "  Keycloak: ${keycloak_url}"
  info "  Backend:  ${backend_url}"
  info "  Logger:   ${logger_url}"
  info "  Syslog:   ${syslog_url}"
  info "  Router:   ${router_url}"
  
  local json_payload
  json_payload=$(cat <<EOF
{
  "id": "${vault_secret_id}",
  "name": "${vault_secret_id}",
  "type": "Password",
  "data": "Empty",
  "metadata": {
    "api.keycloak.url": "${keycloak_url}",
    "api.license.url": "http://unicnet.license",
    "api.backend.url": "${backend_url}",
    "api.logger.url": "${logger_url}",
    "api.syslog.url": "${syslog_url}",
    "KeyCloak.AdmUn": "${kc_admin_user}",
    "KeyCloak.AdmPw": "${kc_admin_pass}",
    "KeyCloak.Realm": "${kc_realm}",
    "RouterHotSpot": "${router_hostport}"
  },
  "tags": [],
  "expiresAt": "2050-12-31T23:59:59.999Z"
}
EOF
)
  
  log "Создаю секрет в Vault с ID: ${vault_secret_id}"
  
  # Выводим запрос на экран
  echo
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Запрос для создания секрета в Vault:"
  info "URL: http://localhost:80/api/Secrets"
  info "Method: POST"
  info "Authorization: Bearer ${VAULT_TOKEN}"
  info "Payload:"
  echo "$json_payload" | sed 's/^/  /'
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  
  local vault_api_url="http://localhost:80/api/Secrets"
  local response
  local temp_json
  temp_json="$(mktemp)"
  echo "$json_payload" > "$temp_json"
  
  docker cp "$temp_json" "${container_name}:/tmp/vault_secret.json" >/dev/null 2>&1 || {
    rm -f "$temp_json"
    err "Не удалось скопировать JSON в контейнер"
    return 1
  }
  
  response="$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" "${container_name}" sh -c 'curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "http://localhost:80/api/Secrets" \
    -H "accept: text/plain" \
    -H "Authorization: Bearer ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @/tmp/vault_secret.json' 2>&1)" || {
    docker exec "${container_name}" rm -f /tmp/vault_secret.json >/dev/null 2>&1 || true
    rm -f "$temp_json"
    err "Ошибка выполнения curl запроса в контейнере"
    return 1
  }
  
  docker exec "${container_name}" rm -f /tmp/vault_secret.json >/dev/null 2>&1 || true
  rm -f "$temp_json"
  
  local http_code
  http_code="$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2 || echo "")"
  local response_body
  response_body="$(echo "$response" | sed '/HTTP_CODE:/d')"
  
  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    log "Секрет '${vault_secret_id}' успешно создан в Vault"
    if [ -n "$response_body" ]; then
      info "Ответ сервера:"
      echo "$response_body" | sed 's/^/  /' | head -10
    fi
    return 0
  elif [ "$http_code" = "409" ]; then
    warn "Секрет '${vault_secret_id}' уже существует в Vault"
    return 0
  else
    err "Ошибка создания секрета в Vault, HTTP ${http_code:-unknown}"
    if [ -n "$response_body" ]; then
      err "Ответ сервера:"
      echo "$response_body" | sed 's/^/  /' | head -20
    fi
    return 1
  fi
}

# =========================
# Step 8: Определение порта/схемы Keycloak
# =========================
step_detect_kc_port() {
  local cf; cf="$(compose_file_abs)"
  local envf; envf="$(env_file_abs)"
  local KC_SVC http_port https_port
  KC_SVC="$(docker_compose -f "$cf" ps --services | grep -i keycloak | head -n1 || true)"

  if [ -n "$KC_SVC" ]; then
    http_port="$(docker_compose -f "$cf" port "$KC_SVC" 8080 | awk -F: 'NF{print $NF; exit}' || true)"
    https_port="$(docker_compose -f "$cf" port "$KC_SVC" 8443 | awk -F: 'NF{print $NF; exit}' || true)"
  fi

  local env_port=""
  if [ -f "$envf" ] && grep -qE '^KEYCLOAK_PORT=' "$envf"; then
    env_port="$(grep -E '^KEYCLOAK_PORT=' "$envf" | tail -1 | cut -d= -f2)"
  fi

  # Определяем IP адрес для доступа к Keycloak
  # Пробуем получить IP из docker network или используем localhost
  local server_ip="localhost"
  if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
    local network_ip
    network_ip="$(docker network inspect "$DOCKER_NETWORK" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null | head -1 || echo "")"
    if [ -n "$network_ip" ] && [ "$network_ip" != "<no value>" ]; then
      server_ip="$network_ip"
    else
      # Пробуем получить IP хоста из контейнера
      local host_ip
      host_ip="$(docker exec unicnet.keycloak sh -c 'ip route | grep default | awk '\''{print $3}'\'' || echo ""' 2>/dev/null | head -1 || echo "")"
      if [ -n "$host_ip" ]; then
        server_ip="$host_ip"
      fi
    fi
  fi
  
  local -a candidates=()
  [ -n "$http_port" ]  && candidates+=("http://${server_ip}:${http_port}")
  [ -n "$https_port" ] && candidates+=("https://${server_ip}:${https_port}")
  [ -n "$env_port" ]   && candidates+=("http://${server_ip}:${env_port}" "https://${server_ip}:${env_port}")
  candidates+=("http://${server_ip}:${KC_PORT_DEFAULT}")

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

# =========================
# Step 9: Ожидание готовности Keycloak
# =========================
step_wait_keycloak() {
  [ -n "${KC_URL:-}" ] || step_detect_kc_port
  log "Ожидание готовности Keycloak на ${KC_URL}"
  wait_kc_ready "${KC_URL}" 60 5 || { 
    err "Keycloak не поднялся на ${KC_URL} по ожидаемым эндпоинтам"
    return 1
  }
  return 0
}

# =========================
# Step 10: Импорт realm
# =========================
step_import_realm() {
  local realm_src; realm_src="$(realm_src_abs)"
  [ -f "$realm_src" ] || { err "Не найден ${realm_src}"; return 1; }
  
  local container_name="unicnet.keycloak"
  
  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    err "Контейнер Keycloak ${container_name} не запущен"
    return 1
  fi
  
  # JSON файл уже содержит внутренние адреса контейнеров, копируем напрямую
  local JSON_REALM
  JSON_REALM="$(json_get_field "$(cat "$realm_src")" "realm" || true)"
  # Если realm не был задан пользователем (остался по умолчанию), берем из JSON
  if [ -n "$JSON_REALM" ]; then
    if [ "$REALM" = "$REALM_DEFAULT" ] || [ -z "$REALM" ]; then
      REALM="$JSON_REALM"
      log "Realm автоматически взят из JSON файла: ${REALM}"
    else
      info "Используется realm, указанный пользователем: ${REALM} (в JSON: ${JSON_REALM})"
    fi
  else
    if [ "$REALM" = "$REALM_DEFAULT" ] || [ -z "$REALM" ]; then
      warn "Realm не найден в JSON файле, используется значение по умолчанию: ${REALM}"
    fi
  fi

  log "Проверяю импорт realm из директории keycloak-import"
  info "JSON файл уже находится в директории app/keycloak-import/ (bind mount)"
  
  sleep 2
  
  local realm_file_path=""
  local possible_paths=(
    "/opt/keycloak/data/import/${REALM}-realm.json"
    "/opt/bitnami/keycloak/data/import/${REALM}-realm.json"
  )
  
  for path in "${possible_paths[@]}"; do
    if docker exec "${container_name}" test -f "$path" 2>/dev/null; then
      realm_file_path="$path"
      info "Файл найден в контейнере: ${realm_file_path}"
      break
    fi
  done
  
  if [ -z "$realm_file_path" ]; then
    warn "Файл не найден в контейнере по ожидаемым путям."
    warn "Попробуйте перезапустить контейнер: docker compose -f $(compose_file_abs) restart unicnet.keycloak"
    warn "Или используйте REST API для импорта."
    
    [ -n "${KC_URL:-}" ] || step_detect_kc_port
    ACCESS_TOKEN="$(kc_get_admin_token || true)"
    if [ -z "$ACCESS_TOKEN" ]; then
      err "Не удалось получить admin token для импорта через REST API"
      return 1
    fi
    
    log "Пробую импорт через REST API (fallback)..."
    local HTTP_CODE response_body
    response_body="$(mktemp)"
    HTTP_CODE="$(curl -s "${CURL_OPTS[@]}" -w "%{http_code}" -X POST "${KC_URL}/admin/realms" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      --data-binary "@${realm_src}" \
      -o "$response_body" 2>&1 | tail -1)"
    
    case "$HTTP_CODE" in
      201) log "Realm '${REALM}' успешно импортирован через REST API." ;;
      409) warn "Realm '${REALM}' уже существует." ;;
      *)   
        err "Ошибка импорта через REST API, HTTP ${HTTP_CODE}"
        if [ -f "$response_body" ] && [ -s "$response_body" ]; then
          err "Ответ сервера:"
          head -30 "$response_body" | sed 's/^/  /'
        fi
        rm -f "$response_body"
        return 1
        ;;
    esac
    rm -f "$response_body"
    return 0
  fi
  
  local kc_cmd=""
  local possible_kc_paths=(
    "/opt/bitnami/keycloak/bin/kc.sh"
    "/opt/keycloak/bin/kc.sh"
    "/opt/jboss/keycloak/bin/kc.sh"
  )
  
  for path in "${possible_kc_paths[@]}"; do
    if docker exec "${container_name}" test -f "$path" 2>/dev/null; then
      kc_cmd="$path"
      break
    fi
  done
  
  if [ -n "$kc_cmd" ]; then
    info "Найдена команда Keycloak: ${kc_cmd}"
    info "Импортирую realm из файла: ${realm_file_path}"
    
    local import_output
    import_output="$(docker exec "${container_name}" \
      "$kc_cmd" import \
      --file "$realm_file_path" \
      --override false 2>&1)" || local import_exit=$?
    
    if [ -n "${import_exit:-}" ] && [ "$import_exit" -ne 0 ]; then
      if echo "$import_output" | grep -qi "already exists\|already imported"; then
        warn "Realm '${REALM}' уже существует — пропускаю импорт."
      else
        err "Ошибка импорта realm через kc.sh:"
        echo "$import_output" | head -30 | sed 's/^/  /'
        return 1
      fi
    else
      if echo "$import_output" | grep -qi "imported\|success"; then
        log "Realm '${REALM}' успешно импортирован через kc.sh import."
      else
        info "Импорт выполнен. Вывод команды:"
        echo "$import_output" | head -20 | sed 's/^/  /'
      fi
    fi
  else
    warn "Команда kc.sh не найдена в контейнере."
    warn "Файл realm скопирован в volume, но автоматический импорт недоступен."
    
    [ -n "${KC_URL:-}" ] || step_detect_kc_port
    ACCESS_TOKEN="$(kc_get_admin_token || true)"
    if [ -n "$ACCESS_TOKEN" ]; then
      log "Пробую импорт через REST API (fallback)..."
      local HTTP_CODE response_body
      response_body="$(mktemp)"
      HTTP_CODE="$(curl -s "${CURL_OPTS[@]}" -w "%{http_code}" -X POST "${KC_URL}/admin/realms" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        --data-binary "@${realm_src}" \
        -o "$response_body" 2>&1 | tail -1)"
      
      case "$HTTP_CODE" in
        201) log "Realm '${REALM}' успешно импортирован через REST API." ;;
        409) warn "Realm '${REALM}' уже существует." ;;
        *)   
          err "Ошибка импорта через REST API, HTTP ${HTTP_CODE}"
          if [ -f "$response_body" ] && [ -s "$response_body" ]; then
            err "Ответ сервера:"
            head -30 "$response_body" | sed 's/^/  /'
          fi
          rm -f "$response_body"
          return 1
          ;;
      esac
      rm -f "$response_body"
    fi
  fi
  
  return 0
}

# =========================
# Step 11: Создание пользователя и назначение 3 групп
# =========================
kc_get_admin_token() {
  # Получаем credentials из контейнера, если они еще не установлены
  if [ -z "${KC_ADMIN:-}" ] || [ -z "${KC_PASS:-}" ]; then
    info "Читаю credentials из контейнера Keycloak..."
    KC_ADMIN="${KC_ADMIN:-$(_get_kc_env KEYCLOAK_ADMIN_USER ${BASE_USER_DEFAULT})}"
    KC_PASS="${KC_PASS:-$(_get_kc_env KEYCLOAK_ADMIN_PASSWORD ${BASE_PASS_DEFAULT})}"
    
    if [ -z "${KC_PASS:-}" ] || [ "${KC_PASS}" = "${BASE_PASS_DEFAULT}" ]; then
      warn "KC_PASS не найден в контейнере, использую значение по умолчанию"
      warn "Если это неверно, установите KC_PASS вручную"
    fi
  fi
  
  [ -n "${KC_URL:-}" ] || { err "KC_URL не установлен"; return 1; }
  [ -n "${KC_ADMIN:-}" ] || { err "KC_ADMIN не установлен"; return 1; }
  [ -n "${KC_PASS:-}" ] || { err "KC_PASS не установлен. Проверьте переменную KEYCLOAK_ADMIN_PASSWORD в контейнере."; return 1; }
  
  info "Получаю токен администратора Keycloak..."
  info "  URL: ${KC_URL}"
  info "  Username: ${KC_ADMIN}"
  if [ ${#CURL_OPTS[@]} -gt 0 ]; then
    info "  CURL_OPTS: ${CURL_OPTS[*]}"
  fi
  
  local -a token_urls=(
    "${KC_URL}/realms/master/protocol/openid-connect/token"
    "${KC_URL}/auth/realms/master/protocol/openid-connect/token"
  )
  
  local token=""
  local last_response=""
  local last_http_code=""
  
  for token_url in "${token_urls[@]}"; do
    info "Пробую: ${token_url}"
    
    local response http_code
    if [ ${#CURL_OPTS[@]} -gt 0 ]; then
      response="$(curl -s -w "\nHTTP_CODE:%{http_code}" "${CURL_OPTS[@]}" \
        --connect-timeout 10 --max-time 30 \
        -X POST "${token_url}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "username=${KC_ADMIN}" \
        --data-urlencode "password=${KC_PASS}" \
        --data-urlencode "grant_type=password" \
        --data-urlencode "client_id=admin-cli" 2>&1)"
    else
      response="$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        --connect-timeout 10 --max-time 30 \
        -X POST "${token_url}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "username=${KC_ADMIN}" \
        --data-urlencode "password=${KC_PASS}" \
        --data-urlencode "grant_type=password" \
        --data-urlencode "client_id=admin-cli" 2>&1)"
    fi
    
    http_code="$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2 || echo "")"
    response="$(echo "$response" | sed '/HTTP_CODE:/d')"
    last_response="$response"
    last_http_code="$http_code"
    
    info "  HTTP код: ${http_code:-unknown}"
    
    token="$(echo "$response" | json_get_access_token 2>/dev/null || echo "")"
    
    if [ -n "$token" ] && [ "$token" != "null" ] && [ "$token" != "empty" ]; then
      log "Токен успешно получен через: ${token_url}"
      echo "$token"
      return 0
    fi
    
    if [ "$http_code" != "200" ] && [ -n "$http_code" ]; then
      if echo "$response" | grep -qiE "error|invalid|unauthorized"; then
        local error_msg
        error_msg="$(json_get_field "$response" "error_description" 2>/dev/null || echo "")"
        if [ -z "$error_msg" ] || [ "$error_msg" = "null" ] || [ "$error_msg" = "empty" ]; then
          error_msg="$(json_get_field "$response" "error" 2>/dev/null || echo "")"
        fi
        if [ -n "$error_msg" ] && [ "$error_msg" != "null" ] && [ "$error_msg" != "empty" ]; then
          warn "Ошибка (HTTP ${http_code}): ${error_msg}"
        else
          warn "Ошибка при запросе токена (HTTP ${http_code})"
        fi
      fi
    fi
  done
  
  err "Не удалось получить токен администратора от Keycloak"
  err "Проверьте:"
  err "  1. Правильность admin username и password"
  err "  2. Что Keycloak полностью запущен и готов"
  err "  3. Что realm 'master' существует"
  err "  4. Что URL Keycloak правильный: ${KC_URL}"
  echo
  
  if [ -n "$last_response" ]; then
    err "Последний ответ сервера (HTTP ${last_http_code:-unknown}):"
    local error_desc error_msg
    error_desc="$(json_get_field "$last_response" "error_description" 2>/dev/null || echo "")"
    if [ -z "$error_desc" ] || [ "$error_desc" = "null" ] || [ "$error_desc" = "empty" ]; then
      error_msg="$(json_get_field "$last_response" "error" 2>/dev/null || echo "")"
    fi
    
    if [ -n "$error_desc" ] && [ "$error_desc" != "null" ] && [ "$error_desc" != "empty" ]; then
      err "Ошибка Keycloak: ${error_desc}"
    elif [ -n "$error_msg" ] && [ "$error_msg" != "null" ] && [ "$error_msg" != "empty" ]; then
      err "Ошибка Keycloak: ${error_msg}"
    else
      echo "$last_response" | head -20 | sed 's/^/  /'
    fi
  else
    err "Пустой ответ от Keycloak"
  fi
  
  return 1
}

step_create_user_and_groups() {
  local container_name="unicnet.keycloak"
  
  # Проверяем, что контейнер запущен
  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$" 2>/dev/null; then
    err "Контейнер ${container_name} не запущен"
    return 1
  fi
  
  # Получаем токен, если его нет (используем логику из get_admin_token.sh)
  if [ -z "${ACCESS_TOKEN:-}" ]; then
    warn "ACCESS_TOKEN не установлен, получаю токен Keycloak..."
    
    # Убеждаемся, что KC_URL установлен
    if [ -z "${KC_URL:-}" ]; then
      info "Определяю URL Keycloak..."
      step_detect_kc_port || {
        err "Не удалось определить URL Keycloak. Убедитесь, что контейнер Keycloak запущен."
        return 1
      }
    fi
    
    # Читаем credentials из контейнера (прямой подход как в get_admin_token.sh)
    info "Читаю credentials из контейнера..."
    local kc_admin kc_pass
    kc_admin="$(_get_kc_env KEYCLOAK_ADMIN_USER ${BASE_USER_DEFAULT})"
    kc_pass="$(_get_kc_env KEYCLOAK_ADMIN_PASSWORD "")"
    
    # Если не нашли в контейнере, используем сохраненные значения
    if [ -z "$kc_admin" ] || [ "$kc_admin" = "${BASE_USER_DEFAULT}" ]; then
      kc_admin="${KC_ADMIN:-${BASE_USER_DEFAULT}}"
    fi
    if [ -z "$kc_pass" ]; then
      kc_pass="${KC_PASS:-}"
    fi
    
    if [ -z "$kc_pass" ]; then
      err "Не удалось прочитать KEYCLOAK_ADMIN_PASSWORD из контейнера"
      err "Проверьте переменные окружения: docker exec ${container_name} env | grep KEYCLOAK"
      return 1
    fi
    
    log "Admin Username: ${kc_admin}"
    log "Admin Password: ******** (${#kc_pass} символов)"
    info "Keycloak URL: ${KC_URL}"
    
    # Получаем токен (прямой подход как в get_admin_token.sh)
    info "Получаю токен администратора..."
    
    local token_urls=(
      "${KC_URL}/realms/master/protocol/openid-connect/token"
      "${KC_URL}/auth/realms/master/protocol/openid-connect/token"
    )
    
    local token=""
    local last_response=""
    local last_http_code=""
    
    for token_url in "${token_urls[@]}"; do
      info "Пробую: ${token_url}"
      
      local response http_code
      # Используем простой curl без CURL_OPTS (как в get_admin_token.sh)
      response="$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        --connect-timeout 10 --max-time 30 \
        -X POST "${token_url}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "username=${kc_admin}" \
        --data-urlencode "password=${kc_pass}" \
        --data-urlencode "grant_type=password" \
        --data-urlencode "client_id=admin-cli" 2>&1)"
      
      http_code="$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2 || echo "")"
      response="$(echo "$response" | sed '/HTTP_CODE:/d')"
      last_response="$response"
      last_http_code="$http_code"
      
      info "  HTTP код: ${http_code:-unknown}"
      
      if [ "$http_code" = "200" ]; then
        # Извлекаем токен (как в get_admin_token.sh)
        if command -v jq >/dev/null 2>&1; then
          token="$(echo "$response" | jq -r '.access_token // empty' 2>/dev/null || echo "")"
        else
          # Используем json_get_access_token как fallback
          token="$(echo "$response" | json_get_access_token 2>/dev/null || echo "")"
          # Если не сработало, пробуем sed
          if [ -z "$token" ] || [ "$token" = "null" ] || [ "$token" = "empty" ]; then
            token="$(echo "$response" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' | head -1)"
          fi
        fi
        
        if [ -n "$token" ] && [ "$token" != "null" ] && [ "$token" != "empty" ]; then
          ACCESS_TOKEN="$token"
          log "Токен успешно получен (длина: ${#ACCESS_TOKEN} символов)"
          break
        else
          warn "HTTP 200, но токен не извлечен. Ответ (первые 200 символов):"
          echo "$response" | head -c 200 | sed 's/^/    /'
          echo
        fi
      else
        if [ -n "$http_code" ] && [ "$http_code" != "200" ]; then
          if echo "$response" | grep -qiE "error|invalid|unauthorized"; then
            local error_msg
            if command -v jq >/dev/null 2>&1; then
              error_msg="$(echo "$response" | jq -r '.error_description // .error // empty' 2>/dev/null || echo "")"
            else
              error_msg="$(json_get_field "$response" "error_description" 2>/dev/null || echo "")"
              if [ -z "$error_msg" ] || [ "$error_msg" = "null" ] || [ "$error_msg" = "empty" ]; then
                error_msg="$(json_get_field "$response" "error" 2>/dev/null || echo "")"
              fi
            fi
            if [ -n "$error_msg" ] && [ "$error_msg" != "null" ] && [ "$error_msg" != "empty" ]; then
              warn "Ошибка (HTTP ${http_code}): ${error_msg}"
            else
              warn "Ошибка при запросе токена (HTTP ${http_code})"
            fi
          fi
        fi
      fi
    done
    
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ] || [ "$ACCESS_TOKEN" = "empty" ]; then
      err "Не удалось получить токен администратора от Keycloak"
      err "Проверьте:"
      err "  1. Правильность admin username и password"
      err "  2. Что Keycloak полностью запущен и готов"
      err "  3. Что realm 'master' существует"
      err "  4. Что URL Keycloak правильный: ${KC_URL}"
      if [ -n "$last_response" ]; then
        err "Последний ответ сервера (HTTP ${last_http_code:-unknown}):"
        echo "$last_response" | head -20 | sed 's/^/  /'
      fi
      return 1
    fi
  fi
  
  # Проверяем наличие realm
  if [ -z "${REALM:-}" ]; then
    REALM="${REALM_DEFAULT}"
    warn "REALM не установлен, использую значение по умолчанию: ${REALM}"
  fi
  
  # Проверяем наличие данных пользователя
  if [ -z "${NEW_USER:-}" ] || [ -z "${NEW_USER_PASS:-}" ]; then
    err "Не установлены данные пользователя (NEW_USER, NEW_USER_PASS)"
    err "Выполните шаг сбора параметров установки"
    return 1
  fi

  log "Создаю пользователя '${NEW_USER}' в realm '${REALM}'"
  local create_resp_headers user_id httpc
  create_resp_headers="$(mktemp)"
  
  # Создаем временный файл для JSON payload
  local json_payload_file
  json_payload_file="$(mktemp)"
  
  cat > "${json_payload_file}" <<EOF
{
  "username": "${NEW_USER}",
  "email": "${NEW_USER_EMAIL}",
  "enabled": true,
  "emailVerified": true,
  "credentials": [{
    "type": "password",
    "value": "${NEW_USER_PASS}",
    "temporary": false
  }]
}
EOF
  
  httpc="$(curl -s "${CURL_OPTS[@]}" -D "${create_resp_headers}" -o /dev/null -w "%{http_code}" \
    -X POST "${KC_URL}/admin/realms/${REALM}/users" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" \
    --data-binary "@${json_payload_file}")"
  
  rm -f "${json_payload_file}"

  case "$httpc" in
    201)
      user_id="$(awk -F'/users/' '/^Location:/ {print $2}' "${create_resp_headers}" | tr -d '\r\n')"
      ;;
    409|200)
      user_id="$(
        curl -s "${CURL_OPTS[@]}" -H "Authorization: Bearer ${ACCESS_TOKEN}" \
          --get --data-urlencode "username=${NEW_USER}" \
          "${KC_URL}/admin/realms/${REALM}/users" \
        | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1
      )"
      ;;
    *)
      err "Создание пользователя вернуло HTTP ${httpc}";;
  esac

  rm -f "${create_resp_headers}"

  if [ -z "${user_id:-}" ]; then
    err "Не удалось определить ID пользователя."; return 1
  fi

  local all_groups_json
  all_groups_json="$(curl -s "${CURL_OPTS[@]}" -H "Authorization: Bearer ${ACCESS_TOKEN}" "${KC_URL}/admin/realms/${REALM}/groups")"

  mapfile -t all_names < <(json_array_get_names "$all_groups_json" "name")
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
    gid="$(json_array_find_id_by_name "$all_groups_json" "$gname" "name" "id")"
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

# =========================
# Step 12: Перезапуск Docker Compose
# =========================
step_restart_compose() {
  local cf; cf="$(compose_file_abs)"
  
  if [ ! -f "${cf}" ]; then
    err "Файл docker-compose.yml не найден: ${cf}"
    return 1
  fi
  
  log "Перезапускаю все сервисы Docker Compose..."
  info "Выполняю: docker compose down && docker compose up -d"
  
  # Используем функцию docker_compose, которая автоматически определяет версию
  if docker_compose -f "$cf" down && docker_compose -f "$cf" up -d; then
    log "Все сервисы успешно перезапущены"
    echo
    docker_compose -f "$cf" ps || true
    return 0
  else
    err "Ошибка при перезапуске сервисов"
    return 1
  fi
}

# =========================
# Дополнительные шаги (1-4, 13-15)
# =========================
step_deps() {
  need_cmd curl || return 1
  need_cmd sed  || return 1
  need_cmd awk  || return 1
  need_cmd grep || return 1
  if ! command -v docker >/dev/null 2>&1; then
    err "Docker не установлен. Установите Docker вручную перед запуском скрипта."; return 1
  fi
  if ! _docker_compose_cmd >/dev/null 2>&1; then
    err "Docker Compose не установлен (не найдена команда docker compose или docker-compose). Установите Docker Compose вручную перед запуском скрипта."; return 1
  fi
  log "Для работы с JSON используется jq через Docker контейнер stedolan/jq"
  log "Зависимости в порядке."; return 0
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

step_docker_login() {
  if [ -z "${YCR_TOKEN:-}" ]; then warn "YCR токен не задан — пропускаю docker login."; return 0; fi
  log "Логин в cr.yandex"; echo "${YCR_TOKEN}" | docker login --username oauth --password-stdin cr.yandex || return 1
  return 0
}

step_compose_up() {
  local cf; cf="$(compose_file_abs)"
  
  # Загружаем переменные окружения из .env файла, если он существует
  local envf; envf="$(env_file_abs)"
  if [ -f "$envf" ]; then
    log "Загружаю переменные окружения из ${envf}"
    set -a  # автоматически экспортировать все переменные
    # shellcheck disable=SC1090
    . "$envf"
    set +a
  fi
  
  # Убеждаемся, что критические переменные MongoDB экспортированы
  export MONGO_INITDB_DATABASE="${MONGO_INITDB_DATABASE:-unicnet_db}"
  export MONGO_UNICNET_DB="${MONGO_UNICNET_DB:-${MONGO_INITDB_DATABASE:-unicnet_db}}"
  export MONGO_UNICNET_USER="${MONGO_UNICNET_USER:-unicnet}"
  export MONGO_UNICNET_PASSWORD="${MONGO_UNICNET_PASSWORD:-unicnet_pass_123}"
  export MONGO_LOGGER_DB="${MONGO_LOGGER_DB:-logger_db}"
  export MONGO_LOGGER_USER="${MONGO_LOGGER_USER:-logger_user}"
  export MONGO_LOGGER_PASSWORD="${MONGO_LOGGER_PASSWORD:-logger_pass_123}"
  export MONGO_VAULT_DB="${MONGO_VAULT_DB:-vault_db}"
  export MONGO_VAULT_USER="${MONGO_VAULT_USER:-vault_user}"
  export MONGO_VAULT_PASSWORD="${MONGO_VAULT_PASSWORD:-vault_pass_123}"
  
  # Проверяем наличие realm JSON в директории keycloak-import (bind mount)
  log "Проверяю наличие realm JSON в директории keycloak-import"
  local realm_src; realm_src="$(realm_src_abs)"
  local keycloak_import_dir
  keycloak_import_dir="$(dirname "$realm_src")"
  
  if [ -f "$realm_src" ]; then
    # Определяем имя realm из JSON для правильного имени файла
    local JSON_REALM
    JSON_REALM="$(json_get_field "$(cat "$realm_src")" "realm" || true)"
    JSON_REALM="${JSON_REALM:-${REALM_DEFAULT}}"
    
    # Переименовываем файл, если нужно (Keycloak ищет файлы вида {realm}-realm.json)
    local expected_name="${keycloak_import_dir}/${JSON_REALM}-realm.json"
    if [ "$realm_src" != "$expected_name" ]; then
      log "Переименовываю realm JSON: $(basename "$realm_src") -> $(basename "$expected_name")"
      cp -f "$realm_src" "$expected_name" || {
        warn "Не удалось переименовать файл, использую существующий"
      }
    fi
    info "Realm JSON файл готов: ${expected_name}"
  else
    warn "JSON realm файл не найден: ${realm_src}"
    warn "Создайте файл в директории app/keycloak-import/"
  fi
  
  log "Запускаю Docker Compose (${cf})"
  info "Используемые переменные MongoDB:"
  info "  MONGO_INITDB_DATABASE=${MONGO_INITDB_DATABASE}"
  info "  MONGO_UNICNET_DB=${MONGO_UNICNET_DB}"
  info "  MONGO_UNICNET_USER=${MONGO_UNICNET_USER}"
  
  # prefer --wait when available
  if docker_compose version >/dev/null 2>&1 && docker_compose --help 2>/dev/null | grep -q -- '--wait'; then
    docker_compose -f "$cf" up -d --wait || return 1
  else
    docker_compose -f "$cf" up -d || return 1
  fi
  echo; docker_compose -f "$cf" ps || true
  return 0
}

step_uninstall_full() {
  local cf
  cf="$(compose_file_abs 2>/dev/null || true)"
  
  log "=== Полная деинсталляция UnicNet Enterprise ==="
  echo
  
  if [ -f "${cf}" ]; then
    # Используем docker-compose down для удаления контейнеров, volumes и образов
    log "Останавливаю и удаляю контейнеры, volumes и образы через docker-compose..."
    
    # Пробуем удалить все сразу (контейнеры, volumes, образы)
    if docker_compose -f "$cf" down --remove-orphans -v --rmi all 2>/dev/null; then
      log "Контейнеры, volumes и образы удалены"
    else
      # Если --rmi all не поддерживается, удаляем контейнеры и volumes
      docker_compose -f "$cf" down --remove-orphans -v 2>/dev/null || true
      log "Контейнеры и volumes удалены"
      
      # Удаляем образы отдельно
      log "Удаляю образы..."
      docker_compose -f "$cf" down --rmi all 2>/dev/null || true
    fi
  else
    warn "Файл docker-compose.yml не найден, удаляю контейнеры вручную..."
    for container in $(docker ps -a --format '{{.Names}}' | grep '^unicnet\.' 2>/dev/null || true); do
      docker rm -f "$container" 2>/dev/null || true
      log "Удален контейнер: $container"
    done
  fi
  
  # Удаляем сеть (docker-compose down не удаляет external сети)
  log "Удаляю сеть Docker..."
  if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
    docker network rm "$DOCKER_NETWORK" 2>/dev/null && log "Сеть $DOCKER_NETWORK удалена" || warn "Не удалось удалить сеть $DOCKER_NETWORK (возможно, к ней подключены другие контейнеры)"
  else
    info "Сеть $DOCKER_NETWORK не существует"
  fi
  
  echo
  log "✅ Полная деинсталляция завершена."
  info "Примечание: Директория репозитория и конфигурационные файлы сохранены."
  return 0
}

step_reinstall_full() { step_uninstall_full || true; run_all; }

step_summary() {
  echo; sep
  echo "ГОТОВО ✅ Проверьте доступы:"
  
  # Определяем IP адрес для доступа к сервисам
  local server_ip="localhost"
  if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
    local network_ip
    network_ip="$(docker network inspect "$DOCKER_NETWORK" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null | head -1 || echo "")"
    if [ -n "$network_ip" ] && [ "$network_ip" != "<no value>" ]; then
      server_ip="$network_ip"
    else
      # Пробуем получить IP хоста из контейнера
      local host_ip
      host_ip="$(docker exec unicnet.keycloak sh -c 'ip route | grep default | awk '\''{print $3}'\'' || echo ""' 2>/dev/null | head -1 || echo "")"
      if [ -n "$host_ip" ]; then
        server_ip="$host_ip"
      fi
    fi
  fi
  
  echo "  Приложение:      http://${server_ip}:${APP_PORT_DEFAULT}"
  # Получаем актуальные credentials из контейнера для вывода
  local kc_admin_display
  kc_admin_display="$(_get_kc_env KEYCLOAK_ADMIN_USER "${KC_ADMIN:-${BASE_USER_DEFAULT}}" 2>/dev/null || echo "${KC_ADMIN:-${BASE_USER_DEFAULT}}")"
  echo "  Keycloak Admin:  ${kc_admin_display} / *** (из контейнера)  (${KC_URL:-http://${server_ip}:${KC_PORT:-$KC_PORT_DEFAULT}})"
  echo "  Realm:           ${REALM}"
  echo "  User:            ${NEW_USER} / ${NEW_USER_PASS}"
  echo "  Groups:          ${ASSIGNED_GROUPS:-<не присвоены>}"
  echo "  Vault Swagger:   http://${server_ip}:8200/swagger/index.html"
  sep
}

# =========================
# Menu
# =========================
run_all() {
  run_step "1/12 Зависимости (Docker, compose)"          step_deps          || true
  run_step "2/12 Создание сети Docker"                            step_create_network|| true
  run_step "3/12 Docker login в Yandex CR (опционально)"          step_docker_login  || true
  run_step "4/12 Запуск Docker Compose"                           step_compose_up    || true
  run_step "5/12 Создание пользователей и БД в MongoDB"           step_create_mongo_users_and_dbs || true
  run_step "6/12 Получение токена Vault"                         step_get_vault_token || true
  run_step "7/12 Создание секрета в Vault"                       step_create_vault_secret || true
  run_step "8/12 Определение схемы/порта Keycloak (http/https)"   step_detect_kc_port|| true
  run_step "9/12 Ожидание готовности Keycloak"                    step_wait_keycloak || true
  run_step "10/12 Импорт realm и получение токена"                 step_import_realm  || true
  run_step "11/12 Создание пользователя и назначение 3 групп"     step_create_user_and_groups || true
  run_step "12/12 Перезапуск Docker Compose"                      step_restart_compose || true
  step_summary
}

main_menu() {
  while true; do
    echo; sep
    echo "Выберите действие:"
    echo "  0) Выполнить всё по порядку"
    echo "  1) Установить зависимости"
    echo "  2) Создать сеть Docker"
    echo "  3) Docker login в Yandex CR"
    echo "  4) Запустить Docker Compose"
    echo "  5) Создать пользователей и БД в MongoDB"
    echo "  6) Получить токен Vault"
    echo "  7) Создать секрет в Vault"
    echo "  8) Определить порт/схему Keycloak"
    echo "  9) Дождаться готовности Keycloak"
    echo " 10) Импортировать realm"
    echo " 11) Создать пользователя и назначение 3 групп"
    echo " 12) Перезапустить Docker Compose (down и up -d)"
    echo " 13) Показать итоги/URL"
    echo " 14) Полная деинсталляция (контейнеры, тома, сеть, образы)"
    echo " 15) Полная переустановка (деинсталляция + установка с нуля)"
    echo "  q) Выход"
    sep
    read -rp "Ваш выбор: " choice || true
    case "$choice" in
      0) run_all ;;
      1) run_step "Зависимости"                          step_deps ;;
      2) run_step "Создание сети Docker"                 step_create_network ;;
      3) run_step "Docker login в Yandex CR"             step_docker_login ;;
      4) run_step "Запуск Docker Compose"                step_compose_up ;;
      5) run_step "Создание пользователей и БД в MongoDB" step_create_mongo_users_and_dbs ;;
      6) run_step "Получение токена Vault"                step_get_vault_token ;;
      7) run_step "Создание секрета в Vault"              step_create_vault_secret ;;
      8) run_step "Определение порта/схемы Keycloak"     step_detect_kc_port ;;
      9) run_step "Ожидание готовности Keycloak"         step_wait_keycloak ;;
      10) run_step "Импорт realm"                         step_import_realm ;;
      11) run_step "Создание пользователя и назначение 3 групп" step_create_user_and_groups ;;
      12) run_step "Перезапуск Docker Compose"             step_restart_compose ;;
      13) step_summary; pause ;;
      14) run_step "Полная деинсталляция" step_uninstall_full ;;
      15) run_step "Полная переустановка" step_reinstall_full ;;
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
 
