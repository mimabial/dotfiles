#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/waybar.vpn.common.sh"

waybar_vpn_load_env

token=""
allow_auto_geolocation=false
vpn_provider="$(waybar_vpn_normalize_provider "${WAYBAR_VPN_PROVIDER:-auto}")"
vpn_state="none"
vpn_info=""
has_vpn_client=false
wireguard_globs=(wg* mullvad*)
openvpn_ifaces=(tun0)

emit_state() {
  local class="$1"
  local text="$2"
  local tooltip="$3"

  cat <<EOF
{ "class": "${class}", "text": "${text}", "tooltip": "${tooltip}" }
EOF
  exit 0
}

require_jq() {
  waybar_have_command jq || emit_state "error" "󰩠" "Error: jq is not installed"
}

load_ipinfo_token() {
  local token_file="${XDG_CONFIG_HOME:-$HOME/.config}/ipinfo.token"
  [[ -f "${token_file}" ]] || return 0
  token="$(tr -d '[:space:]' < "${token_file}")"
}

enable_geolocation_if_allowed() {
  if waybar_vpn_env_flag "${WAYBAR_VPN_ALLOW_AUTO_GEOLOCATION:-false}"; then
    allow_auto_geolocation=true
  fi
}

fetch_ipinfo() {
  local url="https://ipinfo.io/json"
  [[ -n "$token" ]] && url="${url}?token=${token}"
  curl -fsS --max-time 5 "$url" 2>/dev/null
}

render_geolocated_info() {
  local title="$1"
  local gip_data="$2"
  echo "$gip_data" | jq -r "\"<b>${title}</b>\\nIP: \" + .ip + \"\\n\" + .city + \", \" + .region + \", \" + .country"
}

render_basic_info() {
  local title="$1"
  if [[ "${allow_auto_geolocation}" == true ]]; then
    printf '<b>%s</b>\nConnected\nUnable to fetch IP info' "$title"
  else
    printf '<b>%s</b>\nConnected\nLocation lookup disabled' "$title"
  fi
}

check_mullvad() {
  local mullvad_status=""
  local mullvad_status_line=""
  local relay=""
  local location=""
  local ipv4=""

  [[ "${vpn_provider}" == auto || "${vpn_provider}" == mullvad ]] || return 0
  waybar_have_command mullvad || return 0

  has_vpn_client=true
  if ! mullvad_status="$(waybar_mullvad_status)"; then
    vpn_state="error"
    vpn_info="<b>Mullvad VPN Error</b>\nFailed to get status\n${mullvad_status}"
    return 0
  fi

  mullvad_status_line="$(waybar_mullvad_status_line "${mullvad_status}")"

  if [[ "${mullvad_status_line}" == connected* ]]; then
    relay="$(waybar_mullvad_relay "${mullvad_status}")"
    location="$(waybar_mullvad_location "${mullvad_status}")"
    ipv4="$(awk '
      /^[[:space:]]*Visible location:/ {
        for (i = 1; i <= NF; i++) {
          if ($i == "IPv4:") {
            print $(i + 1)
            exit
          }
        }
      }
      /^[[:space:]]*IPv4:/ { print $2; exit }
    ' <<<"${mullvad_status}")"
    vpn_state="connected"
    vpn_info="<b>Mullvad VPN</b>\nRelay: ${relay}\nLocation: ${location}\nIP: ${ipv4}"
    return 0
  fi

  if [[ "${mullvad_status_line}" == disconnected* || "${mullvad_status_line}" == not\ connected* ]]; then
    vpn_state="disconnected"
    vpn_info="<b>Mullvad VPN</b>\nStatus: Disconnected"
  elif [[ "${mullvad_status_line}" == connecting* ]]; then
    vpn_state="connecting"
    vpn_info="<b>Mullvad VPN</b>\nStatus: Connecting..."
  elif [[ "${mullvad_status_line}" == blocked* || "${mullvad_status_line}" == error* ]]; then
    vpn_state="error"
    vpn_info="<b>Mullvad VPN Error</b>\n${mullvad_status}"
  else
    vpn_state="error"
    vpn_info="<b>Mullvad VPN</b>\nUnknown status:\n${mullvad_status}"
  fi

  return 0
}

handle_missing_mullvad_provider() {
  [[ "${vpn_provider}" == mullvad ]] || return 0
  has_vpn_client=true
  vpn_state="error"
  vpn_info="<b>Mullvad VPN Error</b>\nConfigured provider unavailable"
}

check_wireguard() {
  local iface_glob=""
  local iface=""
  local gip_data=""

  [[ "${vpn_state}" != "connected" && "${vpn_state}" != "connecting" ]] || return 0
  [[ "${vpn_provider}" == auto || "${vpn_provider}" == wireguard ]] || return 0

  shopt -s nullglob
  for iface_glob in "${wireguard_globs[@]}"; do
    for iface in /proc/sys/net/ipv4/conf/${iface_glob}; do
      [[ -d "$iface" ]] || continue
      has_vpn_client=true
      vpn_state="connected"
      if [[ "${allow_auto_geolocation}" == true ]] && waybar_have_command curl; then
        gip_data="$(fetch_ipinfo)"
      fi
      if [[ -n "$gip_data" ]]; then
        vpn_info="$(render_geolocated_info "WireGuard VPN" "$gip_data")"
      else
        vpn_info="$(render_basic_info "WireGuard VPN")"
      fi
      shopt -u nullglob
      return 0
    done
  done
  shopt -u nullglob
}

check_openvpn() {
  local iface_name=""
  local gip_data=""

  [[ "${vpn_state}" != "connected" && "${vpn_state}" != "connecting" ]] || return 0
  [[ "${vpn_provider}" == auto || "${vpn_provider}" == openvpn ]] || return 0

  for iface_name in "${openvpn_ifaces[@]}"; do
    [[ -d "/proc/sys/net/ipv4/conf/${iface_name}" ]] || continue
    has_vpn_client=true
    vpn_state="connected"
    if [[ "${allow_auto_geolocation}" == true ]] && waybar_have_command curl; then
      gip_data="$(fetch_ipinfo)"
    fi
    if [[ -n "$gip_data" ]]; then
      vpn_info="$(render_geolocated_info "OpenVPN" "$gip_data")"
    else
      vpn_info="$(render_basic_info "OpenVPN")"
    fi
    return 0
  done
}

emit_vpn_state() {
  case "${vpn_state}" in
    connected) emit_state "connected" "󰳌" "${vpn_info}" ;;
    connecting) emit_state "connecting" "󱆣" "${vpn_info}" ;;
    disconnected) emit_state "disconnected" "󱦛" "${vpn_info}" ;;
    error) emit_state "error" "󰻍" "${vpn_info}" ;;
    none)
      if [[ "${has_vpn_client}" == false ]]; then
        emit_state "none" "󰒙" "No VPN client detected"
      else
        emit_state "disconnected" "󱦛" "VPN disconnected"
      fi
      ;;
  esac
}

case "${vpn_provider}" in
  wireguard|openvpn) has_vpn_client=true ;;
esac

require_jq
load_ipinfo_token
enable_geolocation_if_allowed
check_mullvad
handle_missing_mullvad_provider
check_wireguard
check_openvpn
emit_vpn_state
