#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
declare -F hypr_dbus_get >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/dbus.bash" || exit 1

can_sleep() {
  [[ "$(hypr_login1_call "Can$1" 2>/dev/null)" == *'string "yes"'* ]]
}

case "${1:-}" in
  status)
    suspend=false; { can_sleep Suspend || command -v zzz >/dev/null; } && suspend=true
    hibernate=false; { can_sleep Hibernate || command -v ZZZ >/dev/null; } && hibernate=true
    read -r uptime _ </proc/uptime
    printf '{"suspend":%s,"hibernate":%s,"uptime":%d,"user":"%s","host":"%s"}\n' \
      "${suspend}" "${hibernate}" "${uptime%%.*}" "${USER:-$(id -un)}" "${HOSTNAME}"
    ;;
  screen-off)
    hypr_lua_dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null 2>&1
    ;;
  hibernate)
    "${HYPR_LIB_DIR}/session/lid-close.sh" --no-suspend
    trap '"${HYPR_LIB_DIR}/gaming/gamemode-hook.sh" reconcile >/dev/null 2>&1 || true' EXIT
    hypr_login1_call Hibernate boolean:true >/dev/null 2>&1 && exit 0
    command -v ZZZ >/dev/null && exec ZZZ
    notify_send_safe -u critical 'Hibernate failed' 'No supported hibernate command found'
    exit 1
    ;;
  *) printf 'Usage: hyprshell session/power-menu <status|screen-off|hibernate>\n' >&2; exit 2 ;;
esac
