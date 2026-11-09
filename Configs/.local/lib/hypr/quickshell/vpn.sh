#!/usr/bin/env bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/vpn/settings.bash"
source "${BASH_SOURCE[0]%/*}/vpn/mullvad.bash"
source "${BASH_SOURCE[0]%/*}/vpn/location.bash"
source "${BASH_SOURCE[0]%/*}/vpn/detection.bash"
source "${BASH_SOURCE[0]%/*}/vpn/reconnect.bash"

vpn_json_escape_into() {
  local -n json_escaped_ref="$1"
  local control_char="" unicode_escape=""
  json_escaped_ref="${2//\\/\\\\}"
  json_escaped_ref="${json_escaped_ref//\"/\\\"}"
  while [[ "${json_escaped_ref}" =~ [[:cntrl:]] ]]; do
    control_char="${BASH_REMATCH[0]}"
    printf -v unicode_escape '\\u%04x' "'${control_char}"
    json_escaped_ref="${json_escaped_ref//"${control_char}"/"${unicode_escape}"}"
  done
}

vpn_print_provider_json() {
  local class_name="$1" icon="$2" tooltip=""
  vpn_json_escape_into tooltip "$3"
  printf '{ "class": "%s", "text": "%s", "tooltip": "%s" }\n' "${class_name}" "${icon}" "${tooltip}"
}

vpn_print_status_json() {
  local -n output_status_ref="$1"
  case "${output_status_ref[connection]}" in
    connected) vpn_print_provider_json connected "󰳌" "${output_status_ref[tooltip]}" ;;
    connecting) vpn_print_provider_json connecting "󱆣" "${output_status_ref[tooltip]}" ;;
    disconnected) vpn_print_provider_json disconnected "󱦛" "${output_status_ref[tooltip]}" ;;
    error) vpn_print_provider_json error "󰻍" "${output_status_ref[tooltip]}" ;;
    none)
      if [[ "${output_status_ref[provider_configured_or_detected]}" == false ]]; then
        vpn_print_provider_json none "󰒙" "No VPN client detected"
      else
        vpn_print_provider_json disconnected "󱦛" "VPN disconnected"
      fi
      ;;
  esac
}

declare -A vpn_options=() vpn_status=([connection]=none [tooltip]="" [provider_configured_or_detected]=false)
vpn_load_options_into vpn_options
case "${vpn_options[provider]}" in
  wireguard | openvpn) vpn_status[provider_configured_or_detected]=true ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  vpn_print_provider_json error "󰩠" "Error: jq is not installed"
  exit 0
fi
vpn_detect_mullvad_into vpn_status vpn_options
vpn_detect_interfaces_into vpn_status vpn_options
vpn_record_status_and_reconnect vpn_status vpn_options
vpn_print_status_json vpn_status
