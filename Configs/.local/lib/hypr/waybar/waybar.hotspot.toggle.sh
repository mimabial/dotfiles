#!/usr/bin/env bash

check() {
  command -v "$1" >/dev/null 2>&1
}

notify_hotspot() {
  local title="$1"
  local message="$2"
  local urgency="${3:-normal}"
  local timeout="${4:-5000}"

  dunstify -t "${timeout}" -i "network-wireless" "${title}" "${message}" -u "${urgency}"
}

connection_mode() {
  nmcli -t -f 802-11-wireless.mode connection show "$1" 2>/dev/null | cut -d: -f2
}

active_hotspot_connection() {
  local name="" type="" device=""

  while IFS=: read -r name type device; do
    [[ "${type}" == wifi ]] || continue
    [[ "$(connection_mode "${name}")" == ap ]] || continue
    printf '%s\n' "${name}"
    return 0
  done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)
}

connected_wifi_connection() {
  local wifi_device=""

  wifi_device="$(
    nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
      | awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }'
  )"
  [[ -n "${wifi_device}" ]] || return 1

  nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null \
    | awk -F: -v device="${wifi_device}" '$2 == device { print $1; exit }'
}

saved_hotspot_connection() {
  local name=""

  while IFS= read -r name; do
    [[ "$(connection_mode "${name}")" == ap ]] || continue
    printf '%s\n' "${name}"
    return 0
  done < <(nmcli -t -f NAME connection show 2>/dev/null)
}

restore_wifi_connection() {
  [[ -n "${1:-}" ]] || return 0
  nmcli connection up "$1" 2>/dev/null
}

disable_active_hotspot() {
  local hotspot_name="$1"

  if nmcli connection down "${hotspot_name}" 2>/dev/null; then
    notify_hotspot "Hotspot Disabled" "Disconnected from: ${hotspot_name}"
  else
    notify_hotspot "Hotspot Error" "Failed to disconnect: ${hotspot_name}" critical
  fi
}

disconnect_wifi_for_hotspot() {
  local active_wifi="$1"

  [[ -n "${active_wifi}" ]] || return 0

  notify_hotspot \
    "Hotspot" \
    "You're connected to: ${active_wifi}\n\nDisconnecting WiFi to enable hotspot..."

  if ! nmcli connection down "${active_wifi}" 2>/dev/null; then
    notify_hotspot "Hotspot Error" "Failed to disconnect from WiFi" critical
    return 1
  fi
}

activate_saved_hotspot() {
  local hotspot_name="$1"
  local restore_wifi="$2"
  local error_msg=""

  if error_msg="$(nmcli connection up "${hotspot_name}" 2>&1)"; then
    notify_hotspot "Hotspot Enabled" "Connected to: ${hotspot_name}"
    return 0
  fi

  notify_hotspot "Hotspot Error" "Failed to start: ${hotspot_name}\n\n${error_msg}" critical
  restore_wifi_connection "${restore_wifi}"
  return 1
}

default_hotspot_ssid() {
  printf 'MyHotspot-%s\n' "${HOSTNAME:-$(cat /etc/hostname 2>/dev/null || echo "PC")}"
}

hotspot_connection_password() {
  nmcli --show-secrets -g 802-11-wireless-security.psk,802-11-wireless-security.wep-key0 connection show "$1" 2>/dev/null \
    | awk 'NF && $0 != "--" { print; exit }'
}

notify_created_hotspot() {
  local hotspot_name="$1"
  local hotspot_password="$2"

  if [[ -n "${hotspot_password}" ]]; then
    notify_hotspot \
      "Hotspot Created" \
      "SSID: ${hotspot_name}\nPassword: ${hotspot_password}\n\nUse nm-connection-editor to customize"
    return 0
  fi

  notify_hotspot \
    "Hotspot Created" \
    "SSID: ${hotspot_name}\nPassword saved in NetworkManager\n\nUse nm-connection-editor to customize"
}

create_default_hotspot() {
  local hotspot_name="$1"
  local restore_wifi="$2"
  local error_msg=""
  local hotspot_password=""

  notify_hotspot "Creating Hotspot" "Setting up: ${hotspot_name}"

  if ! error_msg="$(nmcli device wifi hotspot con-name "${hotspot_name}" ssid "${hotspot_name}" 2>&1)"; then
    notify_hotspot "Hotspot Error" "Failed to create hotspot\n\n${error_msg}\n\nTry using nm-connection-editor" critical
    restore_wifi_connection "${restore_wifi}"
    return 1
  fi

  hotspot_password="$(hotspot_connection_password "${hotspot_name}")"
  notify_created_hotspot "${hotspot_name}" "${hotspot_password}"
}

main() {
  local active_hotspot=""
  local active_wifi=""
  local saved_hotspot=""
  local hotspot_name=""

  if ! check nmcli; then
    notify_hotspot "Hotspot Error" "NetworkManager (nmcli) is not installed" critical
    return 1
  fi

  active_hotspot="$(active_hotspot_connection)"
  if [[ -n "${active_hotspot}" ]]; then
    disable_active_hotspot "${active_hotspot}"
    return 0
  fi

  active_wifi="$(connected_wifi_connection)"
  disconnect_wifi_for_hotspot "${active_wifi}" || return 1

  saved_hotspot="$(saved_hotspot_connection)"
  if [[ -n "${saved_hotspot}" ]]; then
    activate_saved_hotspot "${saved_hotspot}" "${active_wifi}"
    return $?
  fi

  hotspot_name="$(default_hotspot_ssid)"
  create_default_hotspot "${hotspot_name}" "${active_wifi}"
  return $?
}

main "$@"
