#!/usr/bin/env bash

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATERC_FILE="${STATE_HOME}/hypr/staterc"
ENV_OVERRIDES_FILE="${STATE_HOME}/hypr/env-overrides"

waybar_vpn_load_env_file() {
  local filepath="$1"
  [[ -r "${filepath}" ]] || return 0

  # shellcheck source=/dev/null
  source "${filepath}"
}

waybar_vpn_load_env() {
  waybar_vpn_load_env_file "${STATERC_FILE}"
  waybar_vpn_load_env_file "${ENV_OVERRIDES_FILE}"
}

waybar_have_command() {
  command -v "$1" >/dev/null 2>&1
}

waybar_notify() {
  local icon="$1"
  local title="$2"
  local message="$3"
  local urgency="${4:-normal}"
  local timeout="${5:-5000}"

  dunstify -t "${timeout}" -i "${icon}" "${title}" "${message}" -u "${urgency}"
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
