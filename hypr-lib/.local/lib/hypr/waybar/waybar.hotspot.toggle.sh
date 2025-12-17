#!/usr/bin/env bash

check() {
  command -v "$1" >/dev/null 2>&1
}

# Check if nmcli is available
if ! check nmcli; then
  notify-send "Hotspot Error" "NetworkManager (nmcli) is not installed" -u critical
  exit 1
fi

# Find active hotspot connection
active_hotspot=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null | grep ':wifi:' | while IFS=: read -r name type device; do
  mode=$(nmcli -t -f 802-11-wireless.mode connection show "$name" 2>/dev/null | cut -d: -f2)
  if [ "$mode" = "ap" ]; then
    echo "$name"
    break
  fi
done)

if [ -n "$active_hotspot" ]; then
  # Hotspot is active - disconnect it
  if nmcli connection down "$active_hotspot" 2>/dev/null; then
    notify-send "Hotspot Disabled" "Disconnected from: $active_hotspot" -u normal
  else
    notify-send "Hotspot Error" "Failed to disconnect: $active_hotspot" -u critical
  fi
else
  # No active hotspot - try to start one

  # Check if WiFi is connected to a network
  wifi_device=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | grep ':wifi:connected' | cut -d: -f1 | head -n1)

  if [ -n "$wifi_device" ]; then
    # Get the active WiFi connection
    active_wifi=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$wifi_device" | cut -d: -f1)

    # Ask user if they want to disconnect from WiFi
    notify-send "Hotspot" "You're connected to: $active_wifi\n\nDisconnecting WiFi to enable hotspot..." -u normal

    # Disconnect from WiFi
    if ! nmcli connection down "$active_wifi" 2>/dev/null; then
      notify-send "Hotspot Error" "Failed to disconnect from WiFi" -u critical
      exit 1
    fi

    sleep 1
  fi

  # Find saved hotspot connections
  saved_hotspots=$(nmcli -t -f NAME connection show 2>/dev/null | while read -r name; do
    mode=$(nmcli -t -f 802-11-wireless.mode connection show "$name" 2>/dev/null | cut -d: -f2)
    if [ "$mode" = "ap" ]; then
      echo "$name"
    fi
  done)

  if [ -n "$saved_hotspots" ]; then
    # Use the first saved hotspot connection
    hotspot_name=$(echo "$saved_hotspots" | head -n1)
    error_msg=$(nmcli connection up "$hotspot_name" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
      notify-send "Hotspot Enabled" "Connected to: $hotspot_name" -u normal
    else
      notify-send "Hotspot Error" "Failed to start: $hotspot_name\n\n$error_msg" -u critical

      # Try to reconnect to WiFi if hotspot failed
      if [ -n "$active_wifi" ]; then
        nmcli connection up "$active_wifi" 2>/dev/null
      fi
    fi
  else
    # No saved hotspot - create a default one
    default_ssid="MyHotspot-${HOSTNAME:-$(cat /etc/hostname 2>/dev/null || echo "PC")}"
    default_password="hotspot123"

    notify-send "Creating Hotspot" "Setting up: $default_ssid" -u normal

    error_msg=$(nmcli device wifi hotspot ssid "$default_ssid" password "$default_password" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
      notify-send "Hotspot Created" "SSID: $default_ssid\nPassword: $default_password\n\nUse nm-connection-editor to customize" -u normal
    else
      notify-send "Hotspot Error" "Failed to create hotspot\n\n$error_msg\n\nTry using nm-connection-editor" -u critical

      # Try to reconnect to WiFi if hotspot failed
      if [ -n "$active_wifi" ]; then
        nmcli connection up "$active_wifi" 2>/dev/null
      fi
    fi
  fi
fi
