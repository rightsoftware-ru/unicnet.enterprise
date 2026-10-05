#!/usr/bin/env bash
# Post-deploy check that services accept tokens signed by the real Vault key.
# Healthchecks cannot see a signing-key mismatch: the service is up and answers
# 401 to everyone (IDX10517). Here a Vault service token must get 200 and an
# anonymous request must get 401. Read-only endpoints only. Tokens are not printed.
set -Eeuo pipefail

vault_url="${VAULT_BOOTSTRAP_URL:-http://127.0.0.1:8200}"
token_path="${VAULT_BOOTSTRAP_TOKEN_PATH:-/api/token/0f8e160416b94225a73f86ac23b9118b}"
owner="${SMOKE_VAULT_OWNER:-UNFrontV2}"
backend_url="${SMOKE_BACKEND_URL:-http://127.0.0.1:30111}"
syslog_url="${SMOKE_SYSLOG_URL:-http://127.0.0.1:8001}"

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

token="$(curl -fsS --max-time 10 --get \
  --data-urlencode "username=$owner" \
  --data-urlencode "role=Service" \
  "$vault_url$token_path" | tr -d '\r\n"')"
if [[ "$token" != eyJ* ]]; then
  echo "[smoke] Vault did not return a JWT for $owner" >&2
  exit 1
fi

failed=0

check() {
  local name="$1" url="$2" anon authed
  anon="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)"
  authed="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -H "Authorization: Bearer $token" "$url" || true)"
  if [[ "$authed" == 200 && "$anon" == 401 ]]; then
    printf '[smoke] %-8s OK   (token=%s anonymous=%s)\n' "$name" "$authed" "$anon"
    return 0
  fi
  printf '[smoke] %-8s FAIL (token=%s anonymous=%s) %s\n' "$name" "$authed" "$anon" "$url" >&2
  if [[ "$authed" == 401 ]]; then
    echo "[smoke]          Vault token rejected: check ${name}'s *__Jwt__SigningKey/Issuer/Audience against VAULT_JWT_* in .env (look for IDX10517 in its logs)" >&2
  fi
  failed=1
}

check backend "$backend_url/api/runbook/device/get_all_cnt"
check syslog "$syslog_url/api/syslog/count"

exit "$failed"
