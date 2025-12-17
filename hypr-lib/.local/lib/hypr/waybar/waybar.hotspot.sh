#!/usr/bin/env bash

check() {
  command -v "$1" >/dev/null 2>&1
}

hotspot_active=false
hotspot_info=""
hotspot_ssid=""
clients=""

# Check NetworkManager hotspot connections
if check nmcli; then
  # Get active hotspot connections (mode: ap)
  active_hotspot=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null | grep ':wifi:' | while IFS=: read -r name type device; do
    # Check if this is an AP mode connection
    mode=$(nmcli -t -f 802-11-wireless.mode connection show "$name" 2>/dev/null | cut -d: -f2)
    if [ "$mode" = "ap" ]; then
      echo "$name|$device"
      break
    fi
  done)

  if [ -n "$active_hotspot" ]; then
    hotspot_active=true
    hotspot_ssid=$(echo "$active_hotspot" | cut -d'|' -f1)
    device=$(echo "$active_hotspot" | cut -d'|' -f2)

    # Get connection details
    ip_addr=$(ip -4 addr show "$device" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    # Try to get connected clients from dnsmasq/dhcp leases
    if [ -f /var/lib/misc/dnsmasq.leases ]; then
      client_count=$(grep -c "$device" /var/lib/misc/dnsmasq.leases 2>/dev/null || echo "0")
      if [ "$client_count" -gt 0 ]; then
        clients=$(awk -v dev="$device" '$0 ~ dev {print $4 " (" $2 ")"}' /var/lib/misc/dnsmasq.leases | sed -z 's/\n/\\n  /g')
        clients="\\nClients ($client_count):\\n  $clients"
      fi
    fi

    hotspot_info="<b>Hotspot Active</b>\\nSSID: $hotspot_ssid\\nDevice: $device\\nIP: ${ip_addr:-N/A}$clients"
  fi
fi

# Fallback: Check for ap0 interface (legacy create_ap or other tools)
if [ "$hotspot_active" = false ]; then
  if test -d /proc/sys/net/ipv4/conf/ap0; then
    hotspot_active=true
    ip_addr=$(ip -4 addr show ap0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    hotspot_info="<b>Hotspot Active</b>\\nInterface: ap0\\nIP: ${ip_addr:-N/A}\\n\\n<i>Legacy hotspot detected</i>"
  fi
fi

# Output
if [ "$hotspot_active" = true ]; then
  cat <<EOF
  { "class": "connected", "text": "󱜠", "tooltip": "$hotspot_info" }
EOF
else
  cat <<EOF
  { "class": "disconnected", "text": "󱜡", "tooltip": "Hotspot is not running" }
EOF
fi
