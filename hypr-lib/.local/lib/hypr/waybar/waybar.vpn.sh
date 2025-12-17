#!/usr/bin/env bash

check() {
  command -v "$1" >/dev/null 2>&1
}

check jq || {
  cat <<EOF
  { "class": "error", "text": "󰩠", "tooltip": "Error: jq is not installed" }
EOF
  exit
}

token=""
[ -f "$HOME/.config/ipinfo.token" ] && token="$(cat "$HOME"/.config/ipinfo.token)"

vpn_state="none" # none, disconnected, connected, error
vpn_info=""
has_vpn_client=false

# Check for Mullvad VPN
if check mullvad; then
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
fi

# Fallback: Check for WireGuard interfaces (wg*, mullvad*)
if [ "$vpn_state" != "connected" ] && [ "$vpn_state" != "connecting" ]; then
  shopt -s nullglob
  for iface in /proc/sys/net/ipv4/conf/wg* /proc/sys/net/ipv4/conf/mullvad*; do
    if [ -d "$iface" ]; then
      has_vpn_client=true
      vpn_state="connected"
      gip_data=$(check curl && curl -su "$token": http://ipinfo.io 2>/dev/null)
      if [ -n "$gip_data" ]; then
        vpn_info=$(echo "$gip_data" | jq -r '"<b>WireGuard VPN</b>\nIP: " + .ip + "\n" + .city + ", " + .region + ", " + .country')
      else
        vpn_info="<b>WireGuard VPN</b>\nConnected (unable to fetch IP info)"
      fi
      break
    fi
  done
  shopt -u nullglob
fi

# Fallback: Check for OpenVPN (tun0)
if [ "$vpn_state" != "connected" ] && [ "$vpn_state" != "connecting" ]; then
  if test -d /proc/sys/net/ipv4/conf/tun0; then
    has_vpn_client=true
    vpn_state="connected"
    gip_data=$(check curl && curl -su "$token": http://ipinfo.io 2>/dev/null)
    if [ -n "$gip_data" ]; then
      vpn_info=$(echo "$gip_data" | jq -r '"<b>OpenVPN</b>\nIP: " + .ip + "\n" + .city + ", " + .region + ", " + .country')
    else
      vpn_info="<b>OpenVPN</b>\nConnected (unable to fetch IP info)"
    fi
  fi
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
