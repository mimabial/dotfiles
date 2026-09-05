#!/usr/bin/env bash

set -euo pipefail

source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1

can_sleep() {
  dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 \
    "org.freedesktop.login1.Manager.Can${1}" 2>/dev/null | grep -q 'string "yes"'
}

case "${1:-}" in
  status)
    suspend=false; { can_sleep Suspend || command -v zzz >/dev/null; } && suspend=true
    hibernate=false; { can_sleep Hibernate || command -v ZZZ >/dev/null; } && hibernate=true
    read -r uptime _ </proc/uptime
    printf '{"suspend":%s,"hibernate":%s,"uptime":%d,"user":"%s","host":"%s"}\n' \
      "${suspend}" "${hibernate}" "${uptime%%.*}" "${USER:-$(id -un)}" "$(hostname)"
    ;;
  screen-off)
    sleep 0.4
    hypr_lua_dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null 2>&1 || true
    ;;
  hibernate)
    hyprshell session/lid-close.sh --no-suspend
    trap 'hyprshell gaming/gamemode-hook reconcile >/dev/null 2>&1 || true' EXIT
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager.Hibernate boolean:true >/dev/null 2>&1 && exit 0
    command -v ZZZ >/dev/null && exec ZZZ
    notify_send_safe -u critical 'Hibernate failed' 'No supported hibernate command found'
    exit 1
    ;;
  *) printf 'Usage: %s <status|screen-off|hibernate>\n' "$(basename "$0")" >&2; exit 2 ;;
esac
