#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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
  nmcli -g 802-11-wireless.mode connection show "$1" 2>/dev/null | awk 'NF { print; exit }'
}

waybar_hotspot_is_wifi_connection_type() {
  case "${1:-}" in
    wifi | 802-11-wireless) return 0 ;;
    *) return 1 ;;
  esac
}

waybar_hotspot_active_connection() {
  local name="" type="" device=""

  while IFS=: read -r name type device; do
    waybar_hotspot_is_wifi_connection_type "${type}" || continue
    [[ "$(waybar_hotspot_connection_mode "${name}")" == ap ]] || continue
    printf '%s|%s\n' "${name}" "${device}"
    return 0
  done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)
}

waybar_hotspot_active_connection_for_device() {
  local target_device="$1"
  local name="" type="" device=""

  [[ -n "${target_device}" ]] || return 1

  while IFS=: read -r name type device; do
    [[ "${device}" == "${target_device}" ]] || continue
    waybar_hotspot_is_wifi_connection_type "${type}" || continue
    [[ "$(waybar_hotspot_connection_mode "${name}")" == ap ]] || continue
    printf '%s|%s\n' "${name}" "${device}"
    return 0
  done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)
}

waybar_hotspot_device_ipv4() {
  ip -4 addr show "$1" 2>/dev/null | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}'
}

waybar_hotspot_active_ap_device() {
  local line="" device="" mode="" ssid=""

  waybar_hotspot_have_command iwconfig || return 1

  while IFS= read -r line; do
    if [[ "${line}" =~ ^([^[:space:]]+)[[:space:]] ]]; then
      device="${BASH_REMATCH[1]}"
      mode=""
      ssid=""
    fi

    [[ -n "${device}" ]] || continue

    if [[ "${line}" == *"no wireless extensions."* ]]; then
      device=""
      continue
    fi

    if [[ "${line}" =~ Mode:([^[:space:]]+) ]]; then
      mode="${BASH_REMATCH[1]}"
    fi

    if [[ "${line}" =~ ESSID:\"([^\"]*)\" ]]; then
      ssid="${BASH_REMATCH[1]}"
    fi

    if [[ "${mode}" == "Master" || "${mode}" == "AP" ]]; then
      [[ -n "${ssid}" && "${ssid}" != "off/any" ]] || ssid="N/A"
      printf '%s|%s\n' "${device}" "${ssid}"
      return 0
    fi
  done < <(iwconfig 2>/dev/null)
}
