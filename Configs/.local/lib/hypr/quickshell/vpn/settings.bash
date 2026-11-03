source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/state-read.bash"

vpn_setting_is_enabled() {
  case "${1,,}" in
    true | yes | on | 1 | y | t) return 0 ;;
    *) return 1 ;;
  esac
}

vpn_normalize_provider_into() {
  local -n normalized_provider_ref="$1"
  case "${2,,}" in
    mullvad) normalized_provider_ref=mullvad ;;
    wireguard | wg) normalized_provider_ref=wireguard ;;
    openvpn | ovpn) normalized_provider_ref=openvpn ;;
    none | off | disabled) normalized_provider_ref=none ;;
    *) normalized_provider_ref=auto ;;
  esac
}

vpn_load_options_into() {
  local -n options_ref="$1"
  local selected_provider normalized_provider geolocation_setting reconnect_setting
  state_get_into selected_provider QUICKSHELL_VPN_PROVIDER "${QUICKSHELL_VPN_PROVIDER:-}"
  state_get_into geolocation_setting QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION "${QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION:-}"
  state_get_into reconnect_setting QUICKSHELL_VPN_AUTO_RECONNECT "${QUICKSHELL_VPN_AUTO_RECONNECT:-}"
  vpn_normalize_provider_into normalized_provider "${selected_provider}"
  options_ref=([provider]="${normalized_provider}" [allow_geolocation]=false [auto_reconnect]=false)
  vpn_setting_is_enabled "${geolocation_setting}" && options_ref[allow_geolocation]=true
  vpn_setting_is_enabled "${reconnect_setting}" && options_ref[auto_reconnect]=true
  return 0
}
