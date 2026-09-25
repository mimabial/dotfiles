#!/usr/bin/env bash

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell session/lock-screen [--get] [lockscreen-args...]
Lock the screen via \$LOCKSCREEN under a systemd scope; --get prints the configured command." "$@"

lockscreen="${LOCKSCREEN:-hyprlock}"

case "${1:-}" in
  --get)
    printf '%s\n' "${lockscreen}"
    exit 0
    ;;
esac

hypr_lock_password_managers

# A hyprlock that outlived its lock keeps the scope name taken, wedging every later lock.
if [[ "$(hyprctl locked 2>/dev/null)" == false ]] && stale="$(hypr_user_pgrep -x "${lockscreen}" | head -n1)" && [[ -n "${stale}" ]]; then
  hypr_user_pkill -9 -x "${lockscreen}"
  tail -f --pid="${stale}" /dev/null 2>/dev/null
fi

# Prevent an unlocked hyprlock process from surviving outside its scope.
scope_unit=(-u "lockscreen.scope")

printf 'Executing %s\n' "${lockscreen}"
exec "${HYPR_LIB_DIR}/system/app2unit.sh" "${scope_unit[@]}" -- "${lockscreen}" "$@"
