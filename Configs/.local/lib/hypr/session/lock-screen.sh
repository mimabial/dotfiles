#!/usr/bin/env bash
#
# lock-screen.sh — Lock the screen via $LOCKSCREEN under a systemd scope unit.
#
# Usage:
#   lock-screen.sh [lockscreen-args...]
#   lock-screen.sh --get          # Print configured lockscreen command
#
# Depends on: app2unit.sh, ${LOCKSCREEN:-hyprlock}
#

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

#? Run the lockscreen under a systemd scope unit so an unlocked-but-still-running
#? hyprlock process doesn't survive as a zombie.
scope_unit=(-u "lockscreen.scope")

app2unit="${HYPR_LIB_DIR}/system/app2unit.sh"
wrapper="$(command -v "${lockscreen}.sh" 2>/dev/null || true)"
if [[ -n "${wrapper}" ]]; then
  printf 'Executing %s wrapper: %s\n' "${lockscreen}" "${wrapper}"
  exec "${app2unit}" "${scope_unit[@]}" -- "${wrapper}" "$@"
else
  printf 'Executing %s\n' "${lockscreen}"
  exec "${app2unit}" "${scope_unit[@]}" -- "${lockscreen}" "$@"
fi
