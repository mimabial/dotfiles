#!/usr/bin/env bash

set -euo pipefail

action="${1:-}"

case "${action}" in
  shutdown | poweroff)
    systemctl_action="poweroff"
    ;;
  reboot)
    systemctl_action="reboot"
    ;;
  *)
    printf 'Usage: %s <shutdown|reboot>\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac

hyprshell state clear 're*-required'
hyprshell close-all.sh
exec systemctl "${systemctl_action}" --no-wall
