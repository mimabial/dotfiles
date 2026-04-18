#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/waybar.notify.common.sh"

waybar_hotspot_have_command() {
  waybar_common_have_command "$1"
}

waybar_hotspot_notify() {
  local title="$1"
  local message="$2"
  local urgency="${3:-normal}"
  local timeout="${4:-5000}"

  waybar_common_notify "network-wireless" "${title}" "${message}" "${urgency}" "${timeout}"
}

waybar_hotspot_connection_mode() {
  nmcli -t -f 802-11-wireless.mode connection show "$1" 2>/dev/null | cut -d: -f2
}

waybar_hotspot_active_connection() {
  local name="" type="" device=""

  while IFS=: read -r name type device; do
    [[ "${type}" == wifi ]] || continue
    [[ "$(waybar_hotspot_connection_mode "${name}")" == ap ]] || continue
    printf '%s|%s\n' "${name}" "${device}"
    return 0
  done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)
}
