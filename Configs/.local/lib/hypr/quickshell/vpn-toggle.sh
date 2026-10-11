#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/vpn/settings.bash"
source "${BASH_SOURCE[0]%/*}/vpn/mullvad.bash"

declare -A vpn_options=()
vpn_load_options_into vpn_options
vpn_provider="${vpn_options[provider]}"

if [[ "${vpn_provider}" == none ]]; then
  printf 'VPN toggling is disabled for this host\n' >&2
  exit 0
fi

if [[ "${vpn_provider}" != auto && "${vpn_provider}" != mullvad ]]; then
  printf 'Current host uses %s; toggle only supports Mullvad CLI\n' "${vpn_provider}" >&2
  exit 0
fi

if ! command -v mullvad >/dev/null 2>&1; then
  printf 'Mullvad CLI is unavailable on this host\n' >&2
  exit 0
fi

if ! mullvad_status="$(vpn_mullvad_status)"; then
  printf 'Failed to get Mullvad status: %s\n' "$mullvad_status" >&2
  exit 1
fi

declare -A mullvad=()
vpn_parse_mullvad_status_into mullvad "$mullvad_status"
mullvad_status_line="${mullvad[state]}"

if [[ "${mullvad_status_line}" == connected* || "${mullvad_status_line}" == blocked* || "${mullvad_status_line}" == error* ]]; then
  mullvad disconnect --wait >/dev/null
else
  if command -v nmcli >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    uuid="$(hyprshell system/vpn-networkmanager 2>/dev/null | jq -r '.active.uuid // empty')"
    [[ -z $uuid ]] || hyprshell system/vpn-networkmanager --disconnect "$uuid"
  fi
  mullvad connect --wait >/dev/null
fi
