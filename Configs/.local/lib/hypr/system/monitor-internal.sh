#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

toggle_name="80-internal-disable"
mirror_name="90-internal-mirror"

internal_monitor_required() {
  internal_monitor="$(monitor_internal_name)"
  if [[ -z "${internal_monitor}" ]]; then
    monitor_notify "Monitor" "No internal laptop display found"
    return 1
  fi
}

internal_on() {
  internal_monitor_required || return 1
  monitor_remove_fragment "${toggle_name}"
  monitor_reload
  monitor_notify "Laptop display enabled" "${internal_monitor}"
}

internal_off() {
  internal_monitor_required || return 1

  if ! monitor_has_active_external; then
    monitor_notify "Can't disable laptop display" "No active external display is enabled"
    return 1
  fi

  if monitor_fragment_exists "${mirror_name}"; then
    monitor_remove_fragment "${mirror_name}"
  fi

  monitor_set_fragment "${toggle_name}" "hl.monitor({output = $(monitor_lua_quote "${internal_monitor}"), disabled = true})"
  monitor_reload
  monitor_notify "Laptop display disabled" "${internal_monitor}"
}

internal_recover() {
  internal_monitor_required || return 0
  if ! monitor_has_active_external && monitor_fragment_exists "${toggle_name}"; then
    monitor_remove_fragment "${toggle_name}"
    monitor_reload
    monitor_notify "Laptop display recovered" "${internal_monitor}"
  fi
}

internal_status() {
  internal_monitor_required || return 1
  if monitor_fragment_exists "${toggle_name}"; then
    printf 'off\n'
  else
    printf 'on\n'
  fi
}

case "${1:-toggle}" in
  on)
    internal_on
    ;;
  off)
    internal_off
    ;;
  toggle)
    if monitor_fragment_exists "${toggle_name}"; then
      internal_on
    else
      internal_off
    fi
    ;;
  recover)
    internal_recover
    ;;
  status)
    internal_status
    ;;
  *)
    echo "Usage: $(basename "$0") {on|off|toggle|recover|status}" >&2
    exit 2
    ;;
esac
