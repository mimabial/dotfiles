#!/usr/bin/env bash
# Link facts the Networking service doesn't expose: gateway, DNS, band and
# round-trip latency. Modelled on omarchy-network-status; emits one JSON
# object so the bar can render it without parsing anything.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

DEFAULT_PROBE_HOST="1.1.1.1"
WIFI_6GHZ_MIN_MHZ=5925
WIFI_5GHZ_MIN_MHZ=4900

hypr_help_guard "Usage: hyprshell system/network-status [--probe <host>]
Emit gateway, DNS, band and ping latency as JSON.
  --probe <host>   host used for the internet latency sample (default ${DEFAULT_PROBE_HOST})" "$@"

probe="${DEFAULT_PROBE_HOST}"
[[ "${1:-}" == "--probe" && -n "${2:-}" ]] && probe="$2"

# The interface that actually carries the default route, not the first one up.
route_details="$(ip route get "${probe}" 2>/dev/null || true)"
iface="" gateway="" iface_found=false gateway_found=false
while read -ra route_fields; do
  for ((field_index = 0; field_index < ${#route_fields[@]}; field_index++)); do
    if ! ${iface_found} && [[ "${route_fields[field_index]}" == dev ]]; then
      iface="${route_fields[field_index + 1]:-}" iface_found=true
    fi
    if ! ${gateway_found} && [[ "${route_fields[field_index]}" == via ]]; then
      gateway="${route_fields[field_index + 1]:-}" gateway_found=true
    fi
  done
done <<<"${route_details}"
address=""
read -r _ _ _ address _ < <(ip -o -4 addr show dev "${iface}" 2>/dev/null) || true
profile_iface="$(ip -j -4 route show default | jq -r 'min_by(.metric // 0).dev // empty')"
[[ -n "${profile_iface}" ]] || profile_iface="${iface}"

dns_servers=()
if command -v resolvectl >/dev/null 2>&1 && [[ -n "${iface}" ]]; then
  while IFS= read -r dns_line; do
    dns_line="${dns_line##*:}"
    IFS=' ' read -ra dns_fields <<<"${dns_line}"
    dns_servers+=("${dns_fields[@]}")
  done < <(resolvectl dns "${iface}" 2>/dev/null || true)
fi
# resolvectl is silent without systemd-resolved; NetworkManager writes the real
# list straight to resolv.conf there.
if ((${#dns_servers[@]} == 0)) && [[ -r /etc/resolv.conf ]]; then
  while read -r resolv_key resolv_value _ || [[ -n "${resolv_key}" ]]; do
    [[ "${resolv_key}" == nameserver && -n "${resolv_value}" ]] && dns_servers+=("${resolv_value}")
  done </etc/resolv.conf
fi

band=""
signal=""
if command -v nmcli >/dev/null 2>&1 && [[ -n "${profile_iface}" ]]; then
  # IN-USE marks the connected AP; FREQ tells us which band it sits in.
  wifi_line=""
  while IFS=: read -r in_use wifi_signal wifi_freq _; do
    [[ "${in_use}" == "*" ]] || continue
    wifi_line="${wifi_signal} ${wifi_freq}"
    break
  done < <(nmcli -t -f IN-USE,SIGNAL,FREQ dev wifi list ifname "${profile_iface}" --rescan no 2>/dev/null || true)
  signal="${wifi_line%% *}"
  freq="${wifi_line#* }"
  freq="${freq%% *}"
  [[ "${signal}" =~ ^[0-9]+$ ]] || signal=""
  if [[ "${freq}" =~ ^[0-9]+$ ]]; then
    if ((freq >= WIFI_6GHZ_MIN_MHZ)); then band="6 GHz"; elif ((freq >= WIFI_5GHZ_MIN_MHZ)); then band="5 GHz"; else band="2.4 GHz"; fi
  fi
fi

# Cumulative since the link came up; the caller derives rates from deltas.
rx=""
tx=""
if [[ -n "${iface}" && -d "/sys/class/net/${iface}/statistics" ]]; then
  read -r rx 2>/dev/null <"/sys/class/net/${iface}/statistics/rx_bytes" || true
  read -r tx 2>/dev/null <"/sys/class/net/${iface}/statistics/tx_bytes" || true
fi

uuid=""
autoconnect=""
if command -v nmcli >/dev/null 2>&1 && [[ -n "${profile_iface}" ]]; then
  uuid="$(nmcli -g GENERAL.CON-UUID device show "${profile_iface}" 2>/dev/null || true)"
  uuid="${uuid%%$'\n'*}"
  [[ "${uuid}" == -- ]] && uuid=""
  if [[ -n "${uuid}" ]]; then
    autoconnect="$(nmcli -g connection.autoconnect connection show "${uuid}" 2>/dev/null || true)"
    autoconnect="${autoconnect%%$'\n'*}"
  fi
fi

# Second sample: the first pays ARP plus the Wi-Fi radio waking, reading 20x high.
latency() {
  local host="$1" line="" ms=null loss=null
  [[ -n "${host}" ]] || { printf '{"ms":null,"loss":null}'; return 0; }
  while IFS= read -r line; do
    [[ "${line}" =~ time[=\<][[:space:]]*([^[:space:]]*) ]] && ms="${BASH_REMATCH[1]:-null}"
    [[ "${line}" =~ ([0-9.]+)%\ packet\ loss ]] && loss="${BASH_REMATCH[1]}"
  done < <(LC_ALL=C ping -n -c 2 -i 0.2 -W 1 "${host}" 2>/dev/null || true)
  printf '{"ms":%s,"loss":%s}' "${ms}" "${loss}"
}
exec {router_latency_fd}< <(latency "${gateway}")
internet_ms="$(latency "${probe}")"
IFS= read -r -d '' router_ms <&"${router_latency_fd}" || true
exec {router_latency_fd}<&-

jq -cn \
  --arg iface "${iface}" --arg address "${address}" --arg gateway "${gateway}" \
  --arg profileIface "${profile_iface}" \
  --arg band "${band}" --arg signal "${signal}" \
  --arg rx "${rx}" --arg tx "${tx}" \
  --argjson router "${router_ms}" --argjson internet "${internet_ms}" \
  --arg uuid "${uuid}" --arg autoconnect "${autoconnect}" \
  '{iface: $iface, profileIface: $profileIface, address: $address, gateway: $gateway, band: $band, dns: $ARGS.positional,
    uuid: $uuid, autoconnect: ($autoconnect == "yes"),
    signal: (if $signal == "" then null else ($signal | tonumber) end),
    rx: (if $rx == "" then null else ($rx | tonumber) end),
    tx: (if $tx == "" then null else ($tx | tonumber) end),
    ping: {router: $router.ms, internet: $internet.ms}, packetLoss: $internet.loss}' \
  --args "${dns_servers[@]}"
