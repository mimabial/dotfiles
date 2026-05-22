#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/waybar.notify.common.sh"
# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/waybar.state.common.sh"

waybar_state_init

waybar_vpn_load_env() {
  WAYBAR_VPN_PROVIDER="$(waybar_state_value "WAYBAR_VPN_PROVIDER" "${WAYBAR_VPN_PROVIDER:-}")"
  WAYBAR_VPN_ALLOW_AUTO_GEOLOCATION="$(waybar_state_value "WAYBAR_VPN_ALLOW_AUTO_GEOLOCATION" "${WAYBAR_VPN_ALLOW_AUTO_GEOLOCATION:-}")"
  WAYBAR_VPN_AUTO_RECONNECT="$(waybar_state_value "WAYBAR_VPN_AUTO_RECONNECT" "${WAYBAR_VPN_AUTO_RECONNECT:-}")"
  export WAYBAR_VPN_PROVIDER WAYBAR_VPN_ALLOW_AUTO_GEOLOCATION WAYBAR_VPN_AUTO_RECONNECT
}

waybar_have_command() {
  waybar_common_have_command "$1"
}

waybar_notify() {
  local icon="$1"
  local title="$2"
  local message="$3"
  local urgency="${4:-normal}"
  local timeout="${5:-5000}"

  waybar_common_notify "${icon}" "${title}" "${message}" "${urgency}" "${timeout}"
}

waybar_vpn_env_flag() {
  case "${1:-}" in
    true | TRUE | yes | YES | on | ON | 1 | y | Y | t | T) return 0 ;;
    *) return 1 ;;
  esac
}

waybar_vpn_normalize_provider() {
  case "${1:-auto}" in
    auto | AUTO | "" ) printf '%s\n' auto ;;
    mullvad | MULLVAD) printf '%s\n' mullvad ;;
    wireguard | WIREGUARD | wg | WG) printf '%s\n' wireguard ;;
    openvpn | OPENVPN | ovpn | OVPN) printf '%s\n' openvpn ;;
    none | NONE | off | OFF | disabled | DISABLED) printf '%s\n' none ;;
    *) printf '%s\n' auto ;;
  esac
}

waybar_mullvad_status() {
  mullvad status 2>&1
}

waybar_mullvad_status_line() {
  awk 'NR == 1 { sub(/^[[:space:]]+/, "", $0); print tolower($0); exit }' <<<"$1"
}

waybar_mullvad_relay() {
  awk -F': *' '/^[[:space:]]*Relay:/ { print $2; exit }' <<<"$1"
}

waybar_mullvad_location() {
  sed -nE 's/^[[:space:]]*Visible location:[[:space:]]*(.+)\. IPv4:.*/\1/p' <<<"$1" | head -n1
}
