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

# Best-effort: powering off must not hinge on the compositor being reachable.
if hyprshell window/close-all.sh; then
  waited=0
  while [[ "${waited}" -lt 40 ]]; do
    remaining="$(hyprctl clients -j 2>/dev/null | jq -r 'length' 2>/dev/null || true)"
    if [[ ! "${remaining}" =~ ^[0-9]+$ || "${remaining}" == 0 ]]; then
      break
    fi
    sleep 0.25
    waited=$((waited + 1))
  done
fi

exec systemctl "${systemctl_action}" --no-wall
