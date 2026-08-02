#!/usr/bin/env bash

set -euo pipefail

[[ "${1:-}" == "--no-lock" ]] || hyprshell session/lid-close.sh --no-suspend

if command -v loginctl >/dev/null; then
  exec loginctl suspend
elif command -v zzz >/dev/null; then
  exec zzz
fi
printf 'No supported suspend command found\n' >&2
exit 1
