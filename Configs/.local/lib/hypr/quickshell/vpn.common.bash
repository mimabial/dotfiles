#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/provider-notify.common.bash"
# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/provider-state.common.bash"

quickshell_state_init

vpn_load_env() {
  QUICKSHELL_VPN_PROVIDER="$(quickshell_state_value "QUICKSHELL_VPN_PROVIDER" "${QUICKSHELL_VPN_PROVIDER:-}")"
  QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION="$(quickshell_state_value "QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION" "${QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION:-}")"
  QUICKSHELL_VPN_AUTO_RECONNECT="$(quickshell_state_value "QUICKSHELL_VPN_AUTO_RECONNECT" "${QUICKSHELL_VPN_AUTO_RECONNECT:-}")"
  export QUICKSHELL_VPN_PROVIDER QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION QUICKSHELL_VPN_AUTO_RECONNECT
}

vpn_env_flag() {
  case "${1:-}" in
    true | TRUE | yes | YES | on | ON | 1 | y | Y | t | T) return 0 ;;
    *) return 1 ;;
  esac
}

vpn_normalize_provider() {
  case "${1:-auto}" in
    auto | AUTO | "" ) printf '%s\n' auto ;;
    mullvad | MULLVAD) printf '%s\n' mullvad ;;
    wireguard | WIREGUARD | wg | WG) printf '%s\n' wireguard ;;
    openvpn | OPENVPN | ovpn | OVPN) printf '%s\n' openvpn ;;
    none | NONE | off | OFF | disabled | DISABLED) printf '%s\n' none ;;
    *) printf '%s\n' auto ;;
  esac
}

mullvad_status() {
  mullvad status 2>&1
}

mullvad_status_line() {
  awk 'NR == 1 { sub(/^[[:space:]]+/, "", $0); print tolower($0); exit }' <<<"$1"
}

mullvad_relay() {
  awk -F': *' '/^[[:space:]]*Relay:/ { print $2; exit }' <<<"$1"
}

mullvad_location() {
  sed -nE 's/^[[:space:]]*Visible location:[[:space:]]*(.+)\. IPv4:.*/\1/p' <<<"$1" | head -n1
}
