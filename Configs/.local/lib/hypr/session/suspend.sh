#!/usr/bin/env bash

set -euo pipefail

[[ "${1:-}" == "--no-lock" ]] || hyprshell session/lid-close.sh --no-suspend

if command -v dbus-send >/dev/null && dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:true; then
  exit 0
fi
command -v zzz >/dev/null && exec zzz
printf 'No supported suspend command found\n' >&2
exit 1
