#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

hypr_help_guard "Usage: hyprshell system/start-if-vpn [--timeout SECONDS] [--workspace WS] [--] <argv...>
Run argv only once the VPN tunnel reports connected." "$@"

timeout=90
workspace=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --timeout)
      timeout="${2:-}"
      shift 2
      ;;
    --workspace)
      workspace="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

[[ "$#" -gt 0 ]] || exit 2
[[ "${timeout}" =~ ^[0-9]+$ ]] || exit 2

tunnel_connected() {
  local status
  status="$(mullvad status -j 2>/dev/null)" || return 1
  [[ "${status}" == *'"state":"connected"'* ]]
}

launch_on_workspace() {
  local target="$1"
  shift
  local joined="$*"
  joined="${joined//\\/\\\\}"
  joined="${joined//\'/\\\'}"
  hyprctl dispatch "(function() return hl.dsp.exec_cmd('[workspace ${target} silent] ${joined}') end)()" >/dev/null
}

command -v mullvad >/dev/null 2>&1 || exit 0

# The mullvad daemon and the tunnel both come up after the compositor.
waited=0
until tunnel_connected; do
  if [[ "${waited}" -ge "${timeout}" ]]; then
    if declare -F print_log >/dev/null 2>&1; then
      print_log -sec "startup" -warn "start-if-vpn" "tunnel not connected after ${timeout}s; skipping ${1}"
    fi
    exit 0
  fi
  sleep 2
  waited=$((waited + 2))
done

if [[ -n "${workspace}" ]]; then
  launch_on_workspace "${workspace}" "$@"
  exit 0
fi

exec "$@"
