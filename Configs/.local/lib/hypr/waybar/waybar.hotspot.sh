#!/usr/bin/env bash

check() {
  command -v "$1" >/dev/null 2>&1
}

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

emit_hotspot_json() {
  local state_class="$1"
  local icon_text="$2"
  local tooltip_text="$3"

  printf '{"class":"%s","text":"%s","tooltip":"%s"}\n' \
    "$(json_escape "${state_class}")" \
    "$(json_escape "${icon_text}")" \
    "$(json_escape "${tooltip_text}")"
}

hotspot_active=false
hotspot_info=""
hotspot_ssid=""
clients=""
lease_clients=()

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
      mapfile -t lease_clients < <(
        awk -v dev="$device" '{
          for (i = 1; i <= NF; i++) {
            if ($i == dev) {
              print $4 " (" $2 ")"
              break
            }
          }
        }' /var/lib/misc/dnsmasq.leases 2>/dev/null
      )

      client_count="${#lease_clients[@]}"
      if [ "$client_count" -gt 0 ]; then
        clients="$(printf '%s\n' "${lease_clients[@]}" | sed -z 's/\n/\\n  /g')"
        clients="\\nClients ($client_count):\\n  $clients"
      fi
    fi

    hotspot_info="<b>Hotspot Active</b>\\nSSID: $hotspot_ssid\\nDevice: $device\\nIP: ${ip_addr:-N/A}$clients"
  fi
fi

# Fallback: check for an ap0 interface created by alternate hotspot tools.
if [ "$hotspot_active" = false ]; then
  if test -d /proc/sys/net/ipv4/conf/ap0; then
    hotspot_active=true
    ip_addr=$(ip -4 addr show ap0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    hotspot_info="<b>Hotspot Active</b>\\nInterface: ap0\\nIP: ${ip_addr:-N/A}\\n\\n<i>Legacy hotspot detected</i>"
  fi
fi

# Output
if [ "$hotspot_active" = true ]; then
  emit_hotspot_json "connected" "󱜠" "$hotspot_info"
else
  emit_hotspot_json "disconnected" "󱜡" "Hotspot is not running"
fi
