#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/vpn.common.bash"

vpn_load_env

token=""
allow_auto_geolocation=false
vpn_provider="$(vpn_normalize_provider "${QUICKSHELL_VPN_PROVIDER:-auto}")"
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
  quickshell_provider_have_command jq || emit_state "error" "󰩠" "Error: jq is not installed"
}

load_ipinfo_token() {
  local token_file="${XDG_CONFIG_HOME:-$HOME/.config}/ipinfo.token"
  [[ -f "${token_file}" ]] || return 0
  token="$(tr -d '[:space:]' < "${token_file}")"
}

enable_geolocation_if_allowed() {
  if vpn_env_flag "${QUICKSHELL_VPN_ALLOW_AUTO_GEOLOCATION:-false}"; then
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
  local ipinfo_json="$2"
  echo "$ipinfo_json" | jq -r "\"<b>${title}</b>\\nIP: \" + .ip + \"\\n\" + .city + \", \" + .region + \", \" + .country"
}

render_basic_info() {
  local title="$1"
  if [[ "${allow_auto_geolocation}" == true ]]; then
    printf '<b>%s</b>\nConnected\nUnable to fetch IP info' "$title"
  else
    printf '<b>%s</b>\nConnected\nLocation lookup disabled' "$title"
  fi
}

update_vpn_state_from_mullvad() {
  local mullvad_status=""
  local mullvad_status_line=""
  local relay=""
  local location=""
  local ipv4=""

  [[ "${vpn_provider}" == auto || "${vpn_provider}" == mullvad ]] || return 0
  quickshell_provider_have_command mullvad || return 0

  has_vpn_client=true
  if ! mullvad_status="$(mullvad_status)"; then
    vpn_state="error"
    vpn_info="<b>Mullvad VPN Error</b>\nFailed to get status\n${mullvad_status}"
    return 0
  fi

  mullvad_status_line="$(mullvad_status_line "${mullvad_status}")"

  if [[ "${mullvad_status_line}" == connected* ]]; then
    relay="$(mullvad_relay "${mullvad_status}")"
    location="$(mullvad_location "${mullvad_status}")"
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

# Geolocation is a network round trip, so it is only attempted when the caller
# allows it; without it the tooltip falls back to the interface name alone.
vpn_mark_connected() {
  local label="$1"
  local ipinfo_json=""

  has_vpn_client=true
  vpn_state="connected"
  if [[ "${allow_auto_geolocation}" == true ]] && quickshell_provider_have_command curl; then
    ipinfo_json="$(fetch_ipinfo)"
  fi
  if [[ -n "${ipinfo_json}" ]]; then
    vpn_info="$(render_geolocated_info "${label}" "${ipinfo_json}")"
  else
    vpn_info="$(render_basic_info "${label}")"
  fi
}

update_vpn_state_from_wireguard() {
  local iface_glob=""
  local iface=""

  [[ "${vpn_state}" != "connected" && "${vpn_state}" != "connecting" ]] || return 0
  [[ "${vpn_provider}" == auto || "${vpn_provider}" == wireguard ]] || return 0

  shopt -s nullglob
  for iface_glob in "${wireguard_globs[@]}"; do
    for iface in /proc/sys/net/ipv4/conf/${iface_glob}; do
      [[ -d "$iface" ]] || continue
      vpn_mark_connected "WireGuard VPN"
      shopt -u nullglob
      return 0
    done
  done
  shopt -u nullglob
}

update_vpn_state_from_openvpn() {
  local iface_name=""

  [[ "${vpn_state}" != "connected" && "${vpn_state}" != "connecting" ]] || return 0
  [[ "${vpn_provider}" == auto || "${vpn_provider}" == openvpn ]] || return 0

  for iface_name in "${openvpn_ifaces[@]}"; do
    [[ -d "/proc/sys/net/ipv4/conf/${iface_name}" ]] || continue
    vpn_mark_connected "OpenVPN"
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

# Keep the last state only for optional Mullvad auto-reconnect. Mullvad owns its
# notifications; custom action notifications belong to NetworkManager.
record_vpn_state_and_reconnect_if_needed() {
  local runtime_dir="${HYPR_RUNTIME_DIR:-}"
  local state_file=""
  local previous_state=""

  if [[ -z "${runtime_dir}" ]]; then
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
      runtime_dir="${XDG_RUNTIME_DIR}/hypr"
    else
      runtime_dir="${TMPDIR:-/tmp}/hypr-${UID:-$(id -u)}"
    fi
  fi
  mkdir -p "${runtime_dir}" 2>/dev/null || return 0
  [[ -w "${runtime_dir}" ]] || return 0
  state_file="${runtime_dir}/quickshell-vpn-last"

  [[ -f "${state_file}" ]] && previous_state="$(<"${state_file}")"
  printf '%s\n' "${vpn_state}" >"${state_file}" || true

  case "${previous_state}:${vpn_state}" in
    connected:disconnected | connected:error | connected:none)
      if vpn_env_flag "${QUICKSHELL_VPN_AUTO_RECONNECT:-false}" \
        && quickshell_provider_have_command mullvad; then
        mullvad connect >/dev/null 2>&1 || true
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
update_vpn_state_from_mullvad
handle_missing_mullvad_provider
update_vpn_state_from_wireguard
update_vpn_state_from_openvpn
record_vpn_state_and_reconnect_if_needed
emit_vpn_state
