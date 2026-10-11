#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/dbus.bash"

[[ "${1:-}" == "--no-lock" ]] || hyprshell session/lid-close.sh --no-suspend
trap 'hyprshell gaming/gamemode-hook reconcile >/dev/null 2>&1 || true' EXIT

hyprshell system/removable --unmount-all || {
  notify-send -u critical 'Suspend cancelled' 'A removable drive could not be unmounted'
  exit 1
}

if command -v dbus-send >/dev/null && hypr_login1_call Suspend boolean:true; then
  exit 0
fi
command -v zzz >/dev/null && exec zzz
printf 'No supported suspend command found\n' >&2
exit 1
