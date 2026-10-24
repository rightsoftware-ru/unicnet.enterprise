#!/bin/sh
set -eu
set -a
. /run/unicnet/service.env
set +a
exec /usr/local/bin/docker-entrypoint.sh postgres
