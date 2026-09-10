#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/vpn-status [--settings | --set SETTING on|off]
Emit VPN state as JSON, or read/change Mullvad settings." "$@"

setting_bool() {
  case "${1:-}" in
    *': on' | *': allow') printf true ;;
    *': off' | *': block') printf false ;;
    *) printf null ;;
  esac
}

emit_settings() {
  local auto lock lan
  auto="$(mullvad auto-connect get 2>/dev/null || true)"
  lock="$(mullvad lockdown-mode get 2>/dev/null || true)"
  lan="$(mullvad lan get 2>/dev/null || true)"
  jq -cn --argjson autoconnect "$(setting_bool "${auto}")" \
    --argjson lockdown "$(setting_bool "${lock}")" \
    --argjson lan "$(setting_bool "${lan}")" \
    '{autoconnect: $autoconnect, lockdown: $lockdown, lan: $lan}'
}

case "${1:-}" in
  --settings)
    command -v mullvad >/dev/null 2>&1 || exit 1
    emit_settings
    exit
    ;;
  --set)
    [[ $# -eq 3 && ( $3 == on || $3 == off ) ]] || exit 2
    case "$2" in
      autoconnect) mullvad auto-connect set "$3" >/dev/null ;;
      lockdown) mullvad lockdown-mode set "$3" >/dev/null ;;
      lan) mullvad lan set "$([[ $3 == on ]] && printf allow || printf block)" >/dev/null ;;
      *) exit 2 ;;
    esac
    emit_settings
    exit
    ;;
  "") ;;
  *) exit 2 ;;
esac

if command -v mullvad >/dev/null 2>&1; then
  if raw="$(mullvad status -j 2>/dev/null)" && jq -e 'type == "object"' >/dev/null <<<"${raw}"; then
    jq -c '
      . as $root | (.details | if type == "object" then . else {} end) as $d |
      {provider:"mullvad", state:(if $root.state == "error" then "blocked" else ($root.state // "unknown") end),
       relay:($d.location.hostname // ""),
       endpoint:([($d.endpoint.address // ""), (($d.endpoint.protocol // "") | ascii_upcase)] | map(select(. != "")) | join("/")),
       location:([($d.location.country // ""), ($d.location.city // "")] | map(select(. != "")) | join(", ")),
       address:($d.location.ipv4 // ""), iface:($d.endpoint.tunnel_interface // ""),
       features:($d.feature_indicators // []), lockedDown:($d.locked_down // false), valid:true, error:""}' <<<"${raw}"
  else
    jq -cn '{provider:"mullvad", state:"unknown", valid:false, error:"Mullvad status unavailable"}'
  fi
  exit
elif ip -br link show 2>/dev/null | grep -qE '^(wg[0-9]|tun[0-9])'; then
  iface="$(ip -br link show 2>/dev/null | awk '/^(wg[0-9]|tun[0-9])/ { print $1; exit }')"
  address="$(ip -o -4 addr show dev "${iface}" 2>/dev/null | awk '{ print $4; exit }')"
  jq -cn --arg iface "${iface}" --arg address "${address}" \
    '{provider:"wireguard", state:"connected", iface:$iface, address:$address, features:[], valid:true, error:""}'
  exit
fi

jq -cn '{provider:"none", state:"disconnected", features:[], valid:true, error:""}'
