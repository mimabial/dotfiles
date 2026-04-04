#!/usr/bin/env bash

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/waybar.vpn.common.sh"

waybar_vpn_load_env
vpn_provider="$(waybar_vpn_normalize_provider "${WAYBAR_VPN_PROVIDER:-auto}")"

if [[ "${vpn_provider}" == none ]]; then
  waybar_notify "network-vpn" "VPN Toggle Disabled" "VPN toggling is disabled for this host"
  exit 0
fi

if [[ "${vpn_provider}" != auto && "${vpn_provider}" != mullvad ]]; then
  waybar_notify "network-vpn" "VPN Toggle Unsupported" "Current host uses ${vpn_provider}; toggle script only supports Mullvad CLI"
  exit 0
fi

if ! waybar_have_command mullvad; then
  waybar_notify "network-vpn" "VPN Toggle Unsupported" "Mullvad CLI is unavailable on this host"
  exit 0
fi

if ! mullvad_status="$(waybar_mullvad_status)"; then
  waybar_notify "network-vpn" "VPN Error" "Failed to get Mullvad status\n\n$mullvad_status" critical
  exit 1
fi

# Check if connected
mullvad_status_line="$(waybar_mullvad_status_line "$mullvad_status")"

if [[ "${mullvad_status_line}" == connected* ]]; then
  # Disconnect
  if mullvad disconnect 2>/dev/null; then
    waybar_notify "network-vpn" "VPN Disconnected" "Mullvad VPN has been disconnected"
  else
    waybar_notify "network-vpn" "VPN Error" "Failed to disconnect from Mullvad VPN" critical
  fi
else
  # Connect
  waybar_notify "network-vpn" "VPN Connecting" "Connecting to Mullvad VPN..."

  if ! error_msg="$(mullvad connect 2>&1)"; then
    waybar_notify "network-vpn" "VPN Error" "Failed to connect to Mullvad VPN\n\n$error_msg" critical
    exit 1
  fi

  if ! status="$(waybar_mullvad_status)"; then
    waybar_notify "network-vpn" "VPN Error" "Mullvad accepted the connection request, but status verification failed\n\n$status" critical
    exit 1
  fi

  status_line="$(waybar_mullvad_status_line "$status")"
  if [[ "${status_line}" == connected* ]]; then
    relay="$(waybar_mullvad_relay "$status")"
    location="$(waybar_mullvad_location "$status")"
    waybar_notify "network-vpn" "VPN Connected" "Connected to Mullvad VPN\n\nRelay: $relay\nLocation: $location"
  else
    waybar_notify "network-vpn" "VPN Connecting" "Mullvad accepted the connection request"
  fi
fi
