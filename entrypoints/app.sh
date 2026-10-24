#!/bin/sh
set -eu
set -a
# shellcheck source=/dev/null
. /run/unicnet/service.env
set +a
exec dotnet "$@"
