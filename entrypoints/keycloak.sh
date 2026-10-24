#!/bin/bash
set -eu
set -a
source /run/unicnet/service.env
set +a
rm -f /tmp/unicnet-master-ready
/opt/keycloak/bin/kc.sh start --import-realm &
server=$!
trap 'kill -TERM "$server" 2>/dev/null || true; wait "$server" || true' TERM INT
cfg=$(mktemp -d)
configured=false
for attempt in $(seq 1 90); do
    if ! kill -0 "$server" 2>/dev/null; then
        break
    fi
    # First boot uses the temporary account. Later boots use the permanent service
    # account, because the initializer deletes the temporary account after verification.
    if /opt/keycloak/bin/kcadm.sh config credentials --config "$cfg/kcadm.config" \
        --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" \
        --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1 \
    || /opt/keycloak/bin/kcadm.sh config credentials --config "$cfg/kcadm.config" \
        --server http://localhost:8080 --realm master --user "$UNICNET_SERVICE_USERNAME" \
        --password "$UNICNET_SERVICE_PASSWORD" >/dev/null 2>&1; then
        if /opt/keycloak/bin/kcadm.sh update realms/master --config "$cfg/kcadm.config" \
            -s sslRequired=NONE >/dev/null 2>&1; then
            configured=true
            break
        fi
    fi
    sleep 2
done
rm -f "$cfg/kcadm.config"
rmdir "$cfg"
if [ "$configured" != true ]; then
    echo '[ERR:7AC19D20] Keycloak local setup failed; credentials are hidden.' >&2
    kill -TERM "$server" 2>/dev/null || true
    wait "$server" || true
    exit 1
fi
echo "$server" > /tmp/unicnet-master-ready
wait "$server"
