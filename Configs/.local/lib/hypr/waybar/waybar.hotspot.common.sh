#!/usr/bin/env bash

waybar_hotspot_have_command() {
  command -v "$1" >/dev/null 2>&1
}

waybar_hotspot_notify() {
  local title="$1"
  local message="$2"
  local urgency="${3:-normal}"
  local timeout="${4:-5000}"

  dunstify -t "${timeout}" -i "network-wireless" "${title}" "${message}" -u "${urgency}"
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
