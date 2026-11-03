#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=/dev/null
hypr_lib="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
source "${hypr_lib}/core/dbus.bash"

[[ "${1:-}" == "--no-lock" ]] || "${hypr_lib}/session/lid-close.sh" --no-suspend
trap '"${hypr_lib}/gaming/gamemode-hook.sh" reconcile >/dev/null 2>&1 || true' EXIT

bash "${hypr_lib}/system/removable.sh" --unmount-all || {
  notify-send -u critical 'Suspend cancelled' 'A removable drive could not be unmounted'
  exit 1
}

if command -v dbus-send >/dev/null && hypr_login1_call Suspend boolean:true; then
  exit 0
fi
command -v zzz >/dev/null && exec zzz
printf 'No supported suspend command found\n' >&2
exit 1
