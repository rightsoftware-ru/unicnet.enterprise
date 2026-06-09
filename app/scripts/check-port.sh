#!/bin/sh
set -eu

PORT="${1:?port required}"

if command -v nc >/dev/null 2>&1; then
  nc -z localhost "$PORT"
  exit $?
fi

if (echo >"/dev/tcp/127.0.0.1/$PORT") >/dev/null 2>&1; then
  exit 0
fi

exit 1
