#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

hypr_help_guard "Usage: hyprshell system/monitor-watch
Watch for monitor hotplug events and recover internal/mirror toggles." "$@"

recover_monitor_toggles() {
  "${HYPR_LIB_DIR}/system/monitor-internal.sh" recover || true
  "${HYPR_LIB_DIR}/system/monitor-mirror.sh" recover || true
}

watch_with_socat() {
  local socket_path="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
  [[ -S "${socket_path}" ]] || return 1
  command -v socat >/dev/null 2>&1 || return 1

  socat -U - "UNIX-CONNECT:${socket_path}" | while IFS= read -r event; do
    case "${event}" in
      monitorremoved\>\>* | monitorremovedv2\>\>*)
        recover_monitor_toggles
        ;;
    esac
  done
}

watch_by_polling() {
  local previous_connected=""
  local current_connected=""

  previous_connected="$(monitor_external_connected_name || true)"
  while true; do
    sleep "${HYPR_MONITOR_WATCH_INTERVAL:-3}"
    current_connected="$(monitor_external_connected_name || true)"
    if [[ -n "${previous_connected}" && -z "${current_connected}" ]]; then
      recover_monitor_toggles
    fi
    previous_connected="${current_connected}"
  done
}

if ! watch_with_socat; then
  watch_by_polling
fi
