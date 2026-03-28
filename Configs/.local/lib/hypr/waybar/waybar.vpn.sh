#!/usr/bin/env bash

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/waybar.vpn.common.sh"

waybar_vpn_load_env

check() {
  command -v "$1" >/dev/null 2>&1
}

check jq || {
  cat <<EOF
  { "class": "error", "text": "󰩠", "tooltip": "Error: jq is not installed" }
EOF
  exit 0
}

token=""
[ -f "$HOME/.config/ipinfo.token" ] && token="$(tr -d '[:space:]' < "$HOME"/.config/ipinfo.token)"
allow_auto_geolocation=false
waybar_vpn_env_flag "${WAYBAR_VPN_ALLOW_AUTO_GEOLOCATION:-false}" && allow_auto_geolocation=true
vpn_provider="$(waybar_vpn_normalize_provider "${WAYBAR_VPN_PROVIDER:-auto}")"
wireguard_globs=(wg* mullvad*)
openvpn_ifaces=(tun0)

fetch_ipinfo() {
  local url="https://ipinfo.io/json"
  if [ -n "$token" ]; then
    url="${url}?token=${token}"
  fi
  curl -fsS --max-time 5 "$url" 2>/dev/null
}

vpn_state="none" # none, disconnected, connected, error
vpn_info=""
has_vpn_client=false

case "${vpn_provider}" in
  wireguard | openvpn) has_vpn_client=true ;;
esac

# Check for Mullvad VPN
if [[ "${vpn_provider}" == auto || "${vpn_provider}" == mullvad ]] && check mullvad; then
  has_vpn_client=true
  mullvad_status=$(mullvad status 2>&1)
  mullvad_exit=$?

  if [ $mullvad_exit -ne 0 ]; then
    vpn_state="error"
    vpn_info="<b>Mullvad VPN Error</b>\nFailed to get status\n$mullvad_status"
  elif echo "$mullvad_status" | grep -q "Connected"; then
    vpn_state="connected"
    relay=$(echo "$mullvad_status" | grep "Relay:" | awk '{print $2}')
    location=$(echo "$mullvad_status" | grep "Visible location:" | sed 's/.*Visible location: *//; s/\. IPv4:.*//')
    ipv4=$(echo "$mullvad_status" | grep "IPv4:" | awk '{print $NF}')
    vpn_info="<b>Mullvad VPN</b>\nRelay: $relay\nLocation: $location\nIP: $ipv4"
  elif echo "$mullvad_status" | grep -qi "disconnected\|not connected"; then
    vpn_state="disconnected"
    vpn_info="<b>Mullvad VPN</b>\nStatus: Disconnected"
  elif echo "$mullvad_status" | grep -qi "connecting"; then
    vpn_state="connecting"
    vpn_info="<b>Mullvad VPN</b>\nStatus: Connecting..."
  elif echo "$mullvad_status" | grep -qi "blocked\|error"; then
    vpn_state="error"
    vpn_info="<b>Mullvad VPN Error</b>\n$mullvad_status"
  else
    vpn_state="error"
    vpn_info="<b>Mullvad VPN</b>\nUnknown status:\n$mullvad_status"
  fi
elif [[ "${vpn_provider}" == mullvad ]]; then
  has_vpn_client=true
  vpn_state="error"
  vpn_info="<b>Mullvad VPN Error</b>\nConfigured provider unavailable"
fi

# Fallback: Check for WireGuard interfaces (wg*, mullvad*)
if [[ ("$vpn_state" != "connected" && "$vpn_state" != "connecting") && ("${vpn_provider}" == auto || "${vpn_provider}" == wireguard) ]]; then
  shopt -s nullglob
  for iface_glob in "${wireguard_globs[@]}"; do
    for iface in /proc/sys/net/ipv4/conf/${iface_glob}; do
      if [ -d "$iface" ]; then
        has_vpn_client=true
        vpn_state="connected"
        gip_data=""
        if [[ "${allow_auto_geolocation}" == true ]] && check curl; then
          gip_data=$(fetch_ipinfo)
        fi
        if [ -n "$gip_data" ]; then
          vpn_info=$(echo "$gip_data" | jq -r '"<b>WireGuard VPN</b>\nIP: " + .ip + "\n" + .city + ", " + .region + ", " + .country')
        else
          vpn_info="<b>WireGuard VPN</b>\nConnected"
          if [[ "${allow_auto_geolocation}" == true ]]; then
            vpn_info="${vpn_info}\nUnable to fetch IP info"
          else
            vpn_info="${vpn_info}\nLocation lookup disabled"
          fi
        fi
        break 2
      fi
    done
  done
  shopt -u nullglob
fi

# Fallback: Check for OpenVPN (tun0)
if [[ ("$vpn_state" != "connected" && "$vpn_state" != "connecting") && ("${vpn_provider}" == auto || "${vpn_provider}" == openvpn) ]]; then
  for iface_name in "${openvpn_ifaces[@]}"; do
    if test -d "/proc/sys/net/ipv4/conf/${iface_name}"; then
      has_vpn_client=true
      vpn_state="connected"
      gip_data=""
      if [[ "${allow_auto_geolocation}" == true ]] && check curl; then
        gip_data=$(fetch_ipinfo)
      fi
      if [ -n "$gip_data" ]; then
        vpn_info=$(echo "$gip_data" | jq -r '"<b>OpenVPN</b>\nIP: " + .ip + "\n" + .city + ", " + .region + ", " + .country')
      else
        vpn_info="<b>OpenVPN</b>\nConnected"
        if [[ "${allow_auto_geolocation}" == true ]]; then
          vpn_info="${vpn_info}\nUnable to fetch IP info"
        else
          vpn_info="${vpn_info}\nLocation lookup disabled"
        fi
      fi
      break
    fi
  done
fi

# Output based on state
case "$vpn_state" in
  connected)
    cat <<EOF
  { "class": "connected", "text": "󰳌", "tooltip": "$vpn_info" }
EOF
    ;;
  connecting)
    cat <<EOF
  { "class": "connecting", "text": "󱆣", "tooltip": "$vpn_info" }
EOF
    ;;
  disconnected)
    cat <<EOF
  { "class": "disconnected", "text": "󱦛", "tooltip": "$vpn_info" }
EOF
    ;;
  error)
    cat <<EOF
  { "class": "error", "text": "󰻍", "tooltip": "$vpn_info" }
EOF
    ;;
  none)
    if [ "$has_vpn_client" = false ]; then
      cat <<EOF
  { "class": "none", "text": "󰒙", "tooltip": "No VPN client detected" }
EOF
    else
      cat <<EOF
  { "class": "disconnected", "text": "󱦛", "tooltip": "VPN disconnected" }
EOF
    fi
    ;;
esac
