#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

hypr_help_guard "Usage: hyprshell system/monitor-mirror {on|off|toggle|recover|status}
Mirror the internal display onto a connected external one (default: toggle)." "$@"

toggle_name="90-internal-mirror"
disable_name="80-internal-disable"

mirror_on() {
  local internal_monitor=""
  local external_monitor=""

  internal_monitor="$(monitor_internal_name)"
  external_monitor="$(monitor_external_connected_name)"

  if [[ -z "${internal_monitor}" ]]; then
    monitor_notify "Mirror unavailable" "No internal laptop display found"
    return 1
  fi
  if [[ -z "${external_monitor}" ]]; then
    monitor_notify "Mirror unavailable" "No external display is connected"
    return 1
  fi

  monitor_remove_fragment "${disable_name}"
  monitor_set_fragment "${toggle_name}" "hl.monitor({output = $(monitor_lua_quote "${external_monitor}"), mode = \"preferred\", position = \"auto\", scale = 1, mirror = $(monitor_lua_quote "${internal_monitor}")})"
  monitor_reload
  monitor_notify "Display mirroring enabled" "${external_monitor} mirrors ${internal_monitor}"
}

mirror_off() {
  monitor_remove_fragment "${toggle_name}"
  monitor_reload
  monitor_notify "Display mirroring disabled"
}

mirror_recover() {
  if ! monitor_has_connected_external && monitor_fragment_exists "${toggle_name}"; then
    monitor_remove_fragment "${toggle_name}"
    monitor_reload
    monitor_notify "Display mirror recovered" "External display removed"
  fi
}

mirror_status() {
  if monitor_fragment_exists "${toggle_name}"; then
    printf 'on\n'
  else
    printf 'off\n'
  fi
}

case "${1:-toggle}" in
  on)
    mirror_on
    ;;
  off)
    mirror_off
    ;;
  toggle)
    if monitor_fragment_exists "${toggle_name}"; then
      mirror_off
    else
      mirror_on
    fi
    ;;
  recover)
    mirror_recover
    ;;
  status)
    mirror_status
    ;;
  *)
    echo "Usage: $(basename "$0") {on|off|toggle|recover|status}" >&2
    exit 2
    ;;
esac
