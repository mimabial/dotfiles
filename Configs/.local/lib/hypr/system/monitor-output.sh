#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

usage="Usage: hyprshell system/monitor-output {on|off|toggle|status} OUTPUT [-q|--quiet]
Enable, disable, or query one connected display."
hypr_help_guard "${usage}" "$@"

action="${1:-}"
output="${2:-}"
quiet=0
[[ "${3:-}" == "-q" || "${3:-}" == "--quiet" ]] && quiet=1
[[ "${action}" =~ ^(on|off|toggle|status)$ && -n "${output}" ]] || {
  printf '%s\n' "${usage}" >&2
  exit 2
}

monitors="$(hypr_monitors_json)"
monitor="$(jq -c --arg output "${output}" '[.[] | select(.name == $output)][0] // empty' <<<"${monitors}")"
[[ -n "${monitor}" ]] || {
  ((quiet)) || monitor_notify "Display unavailable" "${output} is not connected"
  exit 1
}

enabled=0
[[ "$(jq -r '.disabled != true' <<<"${monitor}")" == true ]] && enabled=1
enabled_count="$(jq '[.[] | select(.disabled != true)] | length' <<<"${monitors}")"
safe_name="$(monitor_sanitize_name "${output}")"
enable_name="15-output-${safe_name}-enable"
disable_name="85-output-${safe_name}-disable"

remove_fragment_if_present() {
  monitor_fragment_exists "$1" && monitor_remove_fragment "$1"
  return 0
}

output_on() {
  remove_fragment_if_present "${disable_name}"
  remove_fragment_if_present "80-internal-disable"
  remove_fragment_if_present "90-internal-mirror"
  monitor_set_fragment "${enable_name}" "hl.monitor({output = $(monitor_lua_quote "${output}"), mode = \"preferred\", position = \"auto\", scale = \"auto\"})"
  monitor_reload
  ((quiet)) || monitor_notify "Display enabled" "${output}"
}

output_off() {
  if ((enabled_count <= 1)); then
    ((quiet)) || monitor_notify "Can't disable display" "At least one display must stay enabled"
    return 1
  fi
  remove_fragment_if_present "${enable_name}"
  remove_fragment_if_present "90-internal-mirror"
  monitor_set_fragment "${disable_name}" "hl.monitor({output = $(monitor_lua_quote "${output}"), disabled = true})"
  monitor_reload
  ((quiet)) || monitor_notify "Display disabled" "${output}"
}

case "${action}" in
  on) output_on ;;
  off) output_off ;;
  toggle)
    if ((enabled)); then output_off; else output_on; fi
    ;;
  status) ((enabled)) && printf 'on\n' || printf 'off\n' ;;
esac
