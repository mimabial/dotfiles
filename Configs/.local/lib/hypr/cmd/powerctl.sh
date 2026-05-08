#!/usr/bin/env bash
#
# powerctl.sh — Power off or reboot, after clearing wake-required state and closing windows.
#
# Usage:
#   powerctl.sh <shutdown|poweroff|reboot>
#
# Depends on: hyprshell, systemctl
#
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <shutdown|reboot>
EOF
}

action="${1:-}"
case "${action}" in
  shutdown | poweroff) systemctl_action="poweroff" ;;
  reboot)              systemctl_action="reboot"  ;;
  *)                   usage >&2; exit 2          ;;
esac

hyprshell util/state.sh clear 're*-required'
hyprshell window/close-all.sh
exec systemctl "${systemctl_action}" --no-wall
