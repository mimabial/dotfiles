#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell system/monitor-watch
Watch for monitor hotplug events and recover internal/mirror toggles." "$@"

recover_monitor_toggles() {
  hyprmoncfg doctor >/dev/null 2>&1 && return 0
  "${HYPR_LIB_DIR}/system/monitor-internal.sh" recover || true
  "${HYPR_LIB_DIR}/system/monitor-mirror.sh" recover || true
}

nc -U "$(hypr_event_socket)" | while IFS= read -r event; do
  [[ "${event}" != monitorremovedv2\>\>* ]] || recover_monitor_toggles
done
