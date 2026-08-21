#!/usr/bin/env bash
# Link facts the Networking service doesn't expose: gateway, DNS, band and
# round-trip latency. Modelled on omarchy-network-status; emits one JSON
# object so the bar can render it without parsing anything.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/network-status [--probe <host>]
Emit gateway, DNS, band and ping latency as JSON.
  --probe <host>   host used for the internet latency sample (default 1.1.1.1)" "$@"

probe="1.1.1.1"
[[ "${1:-}" == "--probe" && -n "${2:-}" ]] && probe="$2"

# The interface that actually carries the default route, not the first one up.
iface="$(ip route get "${probe}" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
gateway="$(ip route get "${probe}" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')"
address="$(ip -o -4 addr show dev "${iface}" 2>/dev/null | awk '{ print $4; exit }')"

dns_json='[]'
if command -v resolvectl >/dev/null 2>&1 && [[ -n "${iface}" ]]; then
  dns_json="$(resolvectl dns "${iface}" 2>/dev/null \
    | sed 's/^.*: *//' \
    | tr ' ' '\n' \
    | jq -R -s -c 'split("\n") | map(select(length > 0))' || true)"
  [[ -n "${dns_json}" ]] || dns_json='[]'
fi

band=""
signal=""
if command -v nmcli >/dev/null 2>&1 && [[ -n "${iface}" ]]; then
  # IN-USE marks the connected AP; FREQ tells us which band it sits in.
  wifi_line="$(nmcli -t -f IN-USE,SIGNAL,FREQ dev wifi list ifname "${iface}" --rescan no 2>/dev/null \
    | awk -F: '$1 == "*" { print $2 " " $3; exit }' || true)"
  signal="${wifi_line%% *}"
  freq="${wifi_line##* }"
  [[ "${signal}" =~ ^[0-9]+$ ]] || signal=""
  if [[ "${freq}" =~ ^[0-9]+$ ]]; then
    if ((freq >= 5000)); then band="5 GHz"; else band="2.4 GHz"; fi
  fi
fi

# Cumulative since the link came up; the caller derives rates from deltas.
rx=""
tx=""
if [[ -n "${iface}" && -d "/sys/class/net/${iface}/statistics" ]]; then
  rx="$(cat "/sys/class/net/${iface}/statistics/rx_bytes" 2>/dev/null || true)"
  tx="$(cat "/sys/class/net/${iface}/statistics/tx_bytes" 2>/dev/null || true)"
fi

# The active profile, so the panel can show and flip its autoconnect flag.
uuid=""
autoconnect=""
if command -v nmcli >/dev/null 2>&1 && [[ -n "${iface}" ]]; then
  uuid="$(nmcli -g GENERAL.CON-UUID device show "${iface}" 2>/dev/null | head -n 1 || true)"
  [[ -n "${uuid}" ]] && autoconnect="$(nmcli -g connection.autoconnect connection show "${uuid}" 2>/dev/null | head -n 1 || true)"
fi

# One sample each, short deadline: this runs on a timer and must not stall.
latency() {
  local host="$1"
  [[ -n "${host}" ]] || return 0
  LC_ALL=C ping -n -c 1 -W 1 "${host}" 2>/dev/null \
    | awk -F'time[=<]' '/time[=<]/ { split($2, part, " "); print part[1]; exit }' || true
}
router_ms="$(latency "${gateway}")"
internet_ms="$(latency "${probe}")"

jq -cn \
  --arg iface "${iface}" --arg address "${address}" --arg gateway "${gateway}" \
  --arg band "${band}" --arg signal "${signal}" \
  --arg rx "${rx}" --arg tx "${tx}" \
  --arg router "${router_ms}" --arg internet "${internet_ms}" \
  --arg uuid "${uuid}" --arg autoconnect "${autoconnect}" \
  --argjson dns "${dns_json}" \
  '{iface: $iface, address: $address, gateway: $gateway, band: $band, dns: $dns,
    uuid: $uuid, autoconnect: ($autoconnect == "yes"),
    signal: (if $signal == "" then null else ($signal | tonumber) end),
    rx: (if $rx == "" then null else ($rx | tonumber) end),
    tx: (if $tx == "" then null else ($tx | tonumber) end),
    ping: {router: (if $router == "" then null else ($router | tonumber) end),
           internet: (if $internet == "" then null else ($internet | tonumber) end)}}'
