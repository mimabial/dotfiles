#!/usr/bin/env bash

check() {
  command -v "$1" >/dev/null 2>&1
}

# Check if Mullvad CLI is available
if ! check mullvad; then
  notify-send "VPN Error" "Mullvad VPN is not installed" -u critical
  exit 1
fi

# Get current Mullvad status
mullvad_status=$(mullvad status 2>&1)
mullvad_exit=$?

if [ $mullvad_exit -ne 0 ]; then
  notify-send "VPN Error" "Failed to get Mullvad status\n\n$mullvad_status" -u critical
  exit 1
fi

# Check if connected
if echo "$mullvad_status" | grep -q "Connected"; then
  # Disconnect
  if mullvad disconnect 2>/dev/null; then
    notify-send "VPN Disconnected" "Mullvad VPN has been disconnected" -u normal
  else
    notify-send "VPN Error" "Failed to disconnect from Mullvad VPN" -u critical
  fi
else
  # Connect
  notify-send "VPN Connecting" "Connecting to Mullvad VPN..." -u normal

  error_msg=$(mullvad connect 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    # Wait a moment for connection to establish
    sleep 2

    # Get connection details
    status=$(mullvad status 2>/dev/null)
    relay=$(echo "$status" | grep "Relay:" | awk '{print $2}')
    location=$(echo "$status" | grep "Visible location:" | sed 's/.*Visible location: *//; s/\. IPv4:.*//')

    notify-send "VPN Connected" "Connected to Mullvad VPN\n\nRelay: $relay\nLocation: $location" -u normal
  else
    notify-send "VPN Error" "Failed to connect to Mullvad VPN\n\n$error_msg" -u critical
  fi
fi
