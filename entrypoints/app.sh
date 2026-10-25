#!/bin/sh
set -eu
set -a
# shellcheck source=/dev/null
. /run/unicnet/service.env
set +a

# rc-init-test Front calls SysLog with a VaultTokenGen service JWT.
# Supply the matching validation settings missing from the generated SysLog env.
if [ "${1:-}" = "UnicNet.SysLog.dll" ]; then
    : "${SysLog__Jwt__SigningKey:=${Vault__Jwt__SigningKey:?Missing generated JWT signing key}}"
    : "${SysLog__Jwt__Issuer:=${Vault__Jwt__Issuer:?Missing generated JWT issuer}}"
    : "${SysLog__Jwt__Audience:=${Vault__Jwt__Audience:?Missing generated JWT audience}}"
    export SysLog__Jwt__SigningKey SysLog__Jwt__Issuer SysLog__Jwt__Audience
fi

exec dotnet "$@"
