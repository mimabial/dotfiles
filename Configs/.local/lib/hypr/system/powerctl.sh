#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <shutdown|reboot>
EOF
}

action="${1:-}"
case "${action}" in
  shutdown | poweroff) power_action="poweroff" ;;
  reboot)              power_action="reboot"  ;;
  *)                   usage >&2; exit 2      ;;
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

# elogind (Artix) offers the same verbs through loginctl; both route the request
# through the session manager, so neither needs sudo.
if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
  exec systemctl "${power_action}" --no-wall
fi
command -v loginctl >/dev/null 2>&1 && exec loginctl "${power_action}"
exec "${power_action}"
