#!/usr/bin/env bash

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATERC_FILE="${STATE_HOME}/hypr/staterc"
ENV_OVERRIDES_FILE="${STATE_HOME}/hypr/env-overrides"

waybar_vpn_load_env_file() {
  local filepath="$1"
  [[ -r "${filepath}" ]] || return 0

  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "${line}" == \#* ]] && continue
    [[ "${line}" == export\ * ]] && line="${line#export }"
    [[ "${line}" == *=* ]] || continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value#\"}"
      value="${value%\"}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value#\'}"
      value="${value%\'}"
    fi
    export "${key}=${value}"
  done <"${filepath}"
}

waybar_vpn_load_env() {
  waybar_vpn_load_env_file "${STATERC_FILE}"
  waybar_vpn_load_env_file "${ENV_OVERRIDES_FILE}"
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
