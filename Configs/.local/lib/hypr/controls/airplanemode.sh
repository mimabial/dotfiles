#!/usr/bin/env bash

# Airplane mode toggle script
# Toggles both WiFi and Bluetooth on/off

set -u

scr_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${scr_dir}/lib/control.common.bash"

require_cmd rfkill || {
  echo "rfkill is required"
  exit 1
}

# Icons
icon_airplane_on="󰀝"
icon_airplane_off="󰀞"

# Check current state (airplane mode is ON if both wifi AND bluetooth are blocked)
wifi_blocked=$(rfkill list wifi | grep -c "Soft blocked: yes")
bt_blocked=$(rfkill list bluetooth | grep -c "Soft blocked: yes")

if [[ "$wifi_blocked" -gt 0 && "$bt_blocked" -gt 0 ]]; then
    # Airplane mode is ON, turn it OFF (unblock both)
    rfkill unblock wifi
    rfkill unblock bluetooth
    notify-send -a "Airplane Mode" -i "network-wireless-symbolic" "${icon_airplane_off} Airplane Mode" "Disabled - WiFi and Bluetooth restored"
else
    # Airplane mode is OFF, turn it ON (block both)
    rfkill block wifi
    rfkill block bluetooth
    notify-send -a "Airplane Mode" -i "airplane-mode-symbolic" "${icon_airplane_on} Airplane Mode" "Enabled - WiFi and Bluetooth disabled"
fi
