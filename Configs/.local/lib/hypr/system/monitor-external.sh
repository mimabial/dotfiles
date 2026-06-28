#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

hypr_help_guard "Usage: hyprshell system/monitor-external [connected|active|name|active-name]
Query external-display state (default: connected)." "$@"

print_monitor_or_fail() {
  local monitor_name="$1"
  [[ -n "${monitor_name}" ]] || return 1
  printf '%s\n' "${monitor_name}"
}

case "${1:-connected}" in
  connected)
    monitor_has_connected_external
    ;;
  active)
    monitor_has_active_external
    ;;
  name)
    print_monitor_or_fail "$(monitor_external_connected_name)"
    ;;
  active-name)
    print_monitor_or_fail "$(monitor_external_active_name)"
    ;;
  *)
    echo "Usage: $(basename "$0") [connected|active|name|active-name]" >&2
    exit 2
    ;;
esac
