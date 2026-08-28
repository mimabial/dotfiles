#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/waybar.vpn.common.sh"

waybar_vpn_load_env
vpn_provider="$(waybar_vpn_normalize_provider "${WAYBAR_VPN_PROVIDER:-auto}")"

if [[ "${vpn_provider}" == none ]]; then
  printf 'VPN toggling is disabled for this host\n' >&2
  exit 0
fi

if [[ "${vpn_provider}" != auto && "${vpn_provider}" != mullvad ]]; then
  printf 'Current host uses %s; toggle only supports Mullvad CLI\n' "${vpn_provider}" >&2
  exit 0
fi

if ! waybar_have_command mullvad; then
  printf 'Mullvad CLI is unavailable on this host\n' >&2
  exit 0
fi

if ! mullvad_status="$(waybar_mullvad_status)"; then
  printf 'Failed to get Mullvad status: %s\n' "$mullvad_status" >&2
  exit 1
fi

mullvad_status_line="$(waybar_mullvad_status_line "$mullvad_status")"

if [[ "${mullvad_status_line}" == connected* ]]; then
  mullvad disconnect >/dev/null
else
  if waybar_have_command nmcli && waybar_have_command jq; then
    uuid="$(hyprshell system/vpn-networkmanager 2>/dev/null | jq -r '.active.uuid // empty')"
    [[ -z $uuid ]] || hyprshell system/vpn-networkmanager --disconnect "$uuid"
  fi
  mullvad connect >/dev/null
fi
