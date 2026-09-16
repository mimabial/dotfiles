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

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.sh"

no_clients_left() {
  local count=""
  count="$(hyprctl clients -j 2>/dev/null | jq length 2>/dev/null)" || return 0
  [[ "${count}" == 0 ]]
}

# Best-effort: powering off must not hinge on the compositor being reachable.
hyprshell window/close-all.sh && hypr_wait_for 10 'closewindow>>*' no_clients_left || true

# elogind (Artix) offers the same verbs through loginctl; both route the request
# through the session manager, so neither needs sudo.
if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
  exec systemctl "${power_action}" --no-wall
fi
command -v loginctl >/dev/null 2>&1 && exec loginctl "${power_action}"
exec "${power_action}"
