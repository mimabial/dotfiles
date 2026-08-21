#!/usr/bin/env bash
# Structured VPN state for the bar's panel. waybar.vpn.sh already renders a
# status glyph and a pango tooltip; this reports the same facts as JSON so the
# panel can lay them out instead of parsing markup.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/vpn-status
Emit VPN provider, state, relay, location and features as JSON." "$@"

provider="none"
state="disconnected"
relay=""
endpoint=""
location=""
address=""
iface=""
features_json='[]'

field() { sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" <<<"${2-}" | head -n 1; }

if command -v mullvad >/dev/null 2>&1; then
  provider="mullvad"
  raw="$(mullvad status -v 2>/dev/null || true)"
  head_line="$(head -n 1 <<<"${raw}")"
  case "${head_line}" in
    Connected*) state="connected" ;;
    Connecting*) state="connecting" ;;
    Disconnecting*) state="disconnecting" ;;
    Disconnected*) state="disconnected" ;;
    *) [[ -n "${raw}" ]] && state="error" ;;
  esac

  relay="$(field Relay "${raw}")"
  # "cz-prg-wg-101 ([2001:...]:25295/UDP)" — split the hostname from the endpoint.
  endpoint="${relay#* }"
  endpoint="${endpoint#(}"
  endpoint="${endpoint%)}"
  relay="${relay%% *}"
  [[ "${endpoint}" == "${relay}" ]] && endpoint=""

  iface="$(field 'Tunnel interface' "${raw}")"

  # "Czech Republic, Prague. IPv4: 146.70.129.126"
  visible="$(field 'Visible location' "${raw}")"
  location="${visible%%. IPv4:*}"
  [[ "${location}" == "${visible}" ]] && location="${visible%%.*}"
  address="$(sed -n 's/.*IPv4:[[:space:]]*//p' <<<"${visible}" | head -n 1)"

  features="$(field Features "${raw}")"
  if [[ -n "${features}" ]]; then
    features_json="$(tr ',' '\n' <<<"${features}" \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
      | jq -R -s -c 'split("\n") | map(select(length > 0))' || true)"
    [[ -n "${features_json}" ]] || features_json='[]'
  fi
elif ip -br link show 2>/dev/null | grep -qE '^(wg[0-9]|tun[0-9])'; then
  # No provider CLI, but a tunnel is up — report what the link layer knows.
  provider="wireguard"
  state="connected"
  iface="$(ip -br link show 2>/dev/null | awk '/^(wg[0-9]|tun[0-9])/ { print $1; exit }')"
  address="$(ip -o -4 addr show dev "${iface}" 2>/dev/null | awk '{ print $4; exit }')"
fi

jq -cn \
  --arg provider "${provider}" --arg state "${state}" --arg relay "${relay}" \
  --arg endpoint "${endpoint}" --arg location "${location}" \
  --arg address "${address}" --arg iface "${iface}" \
  --argjson features "${features_json}" \
  '{provider: $provider, state: $state, relay: $relay, endpoint: $endpoint,
    location: $location, address: $address, iface: $iface, features: $features}'
