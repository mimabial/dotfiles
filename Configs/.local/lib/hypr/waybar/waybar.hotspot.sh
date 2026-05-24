#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/waybar.hotspot.common.sh"

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
device=""
ip_addr=""

if waybar_hotspot_have_command nmcli; then
  active_hotspot="$(waybar_hotspot_active_connection)"

  if [[ -n "$active_hotspot" ]]; then
    hotspot_active=true
    hotspot_ssid="${active_hotspot%%|*}"
    device="${active_hotspot#*|}"
  fi
fi

if [[ "$hotspot_active" != true ]]; then
  active_ap_device="$(waybar_hotspot_active_ap_device)"

  if [[ -n "$active_ap_device" ]]; then
    hotspot_active=true
    device="${active_ap_device%%|*}"
    hotspot_ssid="${active_ap_device#*|}"
  fi
fi

if [[ "$hotspot_active" == true ]]; then
  ip_addr="$(waybar_hotspot_device_ipv4 "$device")"

  if [[ -f /var/lib/misc/dnsmasq.leases ]]; then
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
    if [[ "$client_count" -gt 0 ]]; then
      clients="$(printf '%s\n' "${lease_clients[@]}" | sed -z 's/\n/\\n  /g')"
      clients="\\nClients ($client_count):\\n  $clients"
    fi
  fi

  hotspot_info="<b>Hotspot Active</b>\\nSSID: $hotspot_ssid\\nDevice: $device\\nIP: ${ip_addr:-N/A}$clients"
fi

if [[ "$hotspot_active" == true ]]; then
  emit_hotspot_json "connected" "󱜠" "$hotspot_info"
else
  emit_hotspot_json "disconnected" "󱜡" "Hotspot is not running"
fi
