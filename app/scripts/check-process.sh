#!/bin/sh
set -eu

PROCESS_NAME="${1:?process name required}"

if command -v pgrep >/dev/null 2>&1; then
  pgrep -f "$PROCESS_NAME" >/dev/null
  exit $?
fi

if ps aux 2>/dev/null | grep -v grep | grep -q "$PROCESS_NAME"; then
  exit 0
fi

exit 1
