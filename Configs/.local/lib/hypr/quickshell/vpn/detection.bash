vpn_detect_mullvad_into() {
  local -n detected_status_ref="$1" detection_options_ref="$2"
  local mullvad_status="" status_line=""
  local -A mullvad=()

  [[ "${detection_options_ref[provider]}" == auto || "${detection_options_ref[provider]}" == mullvad ]] || return 0
  if ! command -v mullvad >/dev/null 2>&1; then
    [[ "${detection_options_ref[provider]}" == mullvad ]] || return 0
    detected_status_ref[provider_configured_or_detected]=true
    detected_status_ref[connection]=error
    detected_status_ref[tooltip]="<b>Mullvad VPN Error</b>\nConfigured provider unavailable"
    return 0
  fi

  detected_status_ref[provider_configured_or_detected]=true
  if ! mullvad_status="$(vpn_mullvad_status)"; then
    detected_status_ref[connection]=error
    detected_status_ref[tooltip]="<b>Mullvad VPN Error</b>\nFailed to get status\n${mullvad_status}"
    return 0
  fi
  vpn_parse_mullvad_status_into mullvad "${mullvad_status}"
  status_line="${mullvad[state]}"
  if [[ "${status_line}" == connected* ]]; then
    detected_status_ref[connection]=connected
    detected_status_ref[tooltip]="<b>Mullvad VPN</b>\nRelay: ${mullvad[relay]}\nLocation: ${mullvad[location]}\nIP: ${mullvad[ipv4]}"
  elif [[ "${status_line}" == disconnected* || "${status_line}" == not\ connected* ]]; then
    detected_status_ref[connection]=disconnected
    detected_status_ref[tooltip]="<b>Mullvad VPN</b>\nStatus: Disconnected"
  elif [[ "${status_line}" == connecting* ]]; then
    detected_status_ref[connection]=connecting
    detected_status_ref[tooltip]="<b>Mullvad VPN</b>\nStatus: Connecting..."
  elif [[ "${status_line}" == blocked* || "${status_line}" == error* ]]; then
    detected_status_ref[connection]=error
    detected_status_ref[tooltip]="<b>Mullvad VPN Error</b>\n${mullvad_status}"
  else
    detected_status_ref[connection]=error
    detected_status_ref[tooltip]="<b>Mullvad VPN</b>\nUnknown status:\n${mullvad_status}"
  fi
}

vpn_detect_interfaces_into() {
  local -n interface_status_ref="$1" interface_options_ref="$2"
  local interface_path
  [[ "${interface_status_ref[connection]}" != connected && "${interface_status_ref[connection]}" != connecting ]] || return 0

  if [[ "${interface_options_ref[provider]}" == auto || "${interface_options_ref[provider]}" == wireguard ]]; then
    shopt -s nullglob
    for interface_path in /proc/sys/net/ipv4/conf/wg* /proc/sys/net/ipv4/conf/mullvad*; do
      [[ -d "${interface_path}" ]] || continue
      vpn_set_connected_status_into "$1" "$2" "WireGuard VPN"
      shopt -u nullglob
      return 0
    done
    shopt -u nullglob
  fi
  if [[ "${interface_options_ref[provider]}" == auto || "${interface_options_ref[provider]}" == openvpn ]]; then
    [[ -d /proc/sys/net/ipv4/conf/tun0 ]] || return 0
    vpn_set_connected_status_into "$1" "$2" "OpenVPN"
  fi
  return 0
}
