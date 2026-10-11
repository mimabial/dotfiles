source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/state-read.bash"

vpn_setting_is_enabled() {
  case "${1,,}" in
    true | yes | on | 1 | y | t) return 0 ;;
    *) return 1 ;;
  esac
}

vpn_normalize_provider() {
  case "${1,,}" in
    mullvad) printf '%s\n' mullvad ;;
    wireguard | wg) printf '%s\n' wireguard ;;
    openvpn | ovpn) printf '%s\n' openvpn ;;
    none | off | disabled) printf '%s\n' none ;;
    *) printf '%s\n' auto ;;
  esac
}

vpn_load_options_into() {
  local -n options_ref="$1"
  local selected_provider geolocation_setting reconnect_setting
  state_get_into selected_provider QUICKSHELL_VPN_PROVIDER "${QUICKSHELL_VPN_PROVIDER:-}"
  state_get_into geolocation_setting QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION "${QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION:-}"
  state_get_into reconnect_setting QUICKSHELL_VPN_AUTO_RECONNECT "${QUICKSHELL_VPN_AUTO_RECONNECT:-}"
  options_ref=([provider]="$(vpn_normalize_provider "${selected_provider}")" [allow_geolocation]=false [auto_reconnect]=false)
  vpn_setting_is_enabled "${geolocation_setting}" && options_ref[allow_geolocation]=true
  vpn_setting_is_enabled "${reconnect_setting}" && options_ref[auto_reconnect]=true
  return 0
}
