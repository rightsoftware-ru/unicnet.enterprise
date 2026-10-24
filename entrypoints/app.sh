#!/bin/sh
set -eu
set -a
. /run/unicnet/service.env
set +a
exec dotnet "$@"
