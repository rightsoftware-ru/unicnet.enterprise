#!/usr/bin/env bash
set -Eeuo pipefail

vault_url="${VAULT_BOOTSTRAP_URL:-http://127.0.0.1:8200}"
values_file="${1:-vault-values.json}"

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
test -r "$values_file" || { echo "Cannot read $values_file" >&2; exit 1; }

for _ in $(seq 1 60); do
  curl -fsS "$vault_url/openapi/v1.json" >/dev/null && break
  sleep 2
done
curl -fsS "$vault_url/openapi/v1.json" >/dev/null

secret_type() {
  case "$1" in
    *ConnectionString*|*PostgresCS*) printf '%s' ConnectionString ;;
    *Url|*URL) printf '%s' URL ;;
    *Password*|*SigningKey*|*License*|*Secret*) printf '%s' Password ;;
    *) printf '%s' ApiKey ;;
  esac
}

while IFS= read -r owner; do
  token="$(curl -fsS --get \
    --data-urlencode "username=$owner" \
    --data-urlencode "role=Service" \
    "$vault_url/api/token/0f8e160416b94225a73f86ac23b9118b" | jq -r '.')"
  names="$(curl -fsS -H "Authorization: Bearer $token" "$vault_url/api/Secrets/names")"

  while IFS= read -r name; do
    value="$(jq -r --arg owner "$owner" --arg name "$name" '.[$owner][$name]' "$values_file")"
    type="$(secret_type "$name")"
    payload="$(jq -n --arg name "$name" --arg type "$type" --arg data "$value" \
      '{name:$name,type:$type,data:$data,metadata:{},tags:["configuration"]}')"
    id="$(jq -r --arg name "$name" '.[$name] // empty' <<<"$names")"

    if [[ -n "$id" ]]; then
      curl -fsS -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
        --data "$payload" "$vault_url/api/Secrets/$id" >/dev/null
      printf 'updated %s/%s\n' "$owner" "$name"
    else
      curl -fsS -X POST -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
        --data "$payload" "$vault_url/api/Secrets" >/dev/null
      printf 'created %s/%s\n' "$owner" "$name"
    fi
  done < <(jq -r --arg owner "$owner" '.[$owner] | keys[]' "$values_file")
done < <(jq -r 'keys[]' "$values_file")

echo "Vault bootstrap completed. Remove vault-values.json from the host after verification."

