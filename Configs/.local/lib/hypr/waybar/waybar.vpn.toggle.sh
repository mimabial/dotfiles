#!/usr/bin/env bash

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/waybar.vpn.common.sh"

check() {
  command -v "$1" >/dev/null 2>&1
}

waybar_vpn_load_env
vpn_provider="$(waybar_vpn_normalize_provider "${WAYBAR_VPN_PROVIDER:-auto}")"

if [[ "${vpn_provider}" == none ]]; then
  dunstify -i "network-vpn" "VPN Toggle Disabled" "VPN toggling is disabled for this host" -u normal
  exit 0
fi

if [[ "${vpn_provider}" != auto && "${vpn_provider}" != mullvad ]]; then
  dunstify -i "network-vpn" "VPN Toggle Unsupported" "Current host uses ${vpn_provider}; toggle script only supports Mullvad CLI" -u normal
  exit 0
fi

if ! check mullvad; then
  dunstify -i "network-vpn" "VPN Toggle Unsupported" "Mullvad CLI is unavailable on this host" -u normal
  exit 0
fi

# Get current Mullvad status
mullvad_status=$(mullvad status 2>&1)
mullvad_exit=$?

if [ $mullvad_exit -ne 0 ]; then
  dunstify -i "network-vpn" "VPN Error" "Failed to get Mullvad status\n\n$mullvad_status" -u critical
  exit 1
fi

# Check if connected
mullvad_status_line="$(awk 'NR == 1 { sub(/^[[:space:]]+/, "", $0); print tolower($0); exit }' <<<"$mullvad_status")"

if [[ "${mullvad_status_line}" == connected* ]]; then
  # Disconnect
  if mullvad disconnect 2>/dev/null; then
    dunstify -t 5000 -i "network-vpn" "VPN Disconnected" "Mullvad VPN has been disconnected" -u normal
  else
    dunstify -i "network-vpn" "VPN Error" "Failed to disconnect from Mullvad VPN" -u critical
  fi
else
  # Connect
  dunstify -t 5000 -i "network-vpn" "VPN Connecting" "Connecting to Mullvad VPN..." -u normal

  error_msg=$(mullvad connect 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    status="$(mullvad status 2>&1)"
    status_exit=$?
    if [ $status_exit -ne 0 ]; then
      dunstify -i "network-vpn" "VPN Error" "Mullvad accepted the connection request, but status verification failed\n\n$status" -u critical
      exit 1
    fi
    status_line="$(awk 'NR == 1 { sub(/^[[:space:]]+/, "", $0); print tolower($0); exit }' <<<"$status")"
    if [[ "${status_line}" == connected* ]]; then
      relay="$(awk -F': *' '/^[[:space:]]*Relay:/ { print $2; exit }' <<<"$status")"
      location="$(sed -nE 's/^[[:space:]]*Visible location:[[:space:]]*(.+)\. IPv4:.*/\1/p' <<<"$status" | head -n1)"
      dunstify -t 5000 -i "network-vpn" "VPN Connected" "Connected to Mullvad VPN\n\nRelay: $relay\nLocation: $location" -u normal
    else
      dunstify -t 5000 -i "network-vpn" "VPN Connecting" "Mullvad accepted the connection request" -u normal
    fi
  else
    dunstify -i "network-vpn" "VPN Error" "Failed to connect to Mullvad VPN\n\n$error_msg" -u critical
  fi
fi
