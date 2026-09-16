#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell system/start-if-vpn [--timeout SECONDS] [--workspace WS] [--] <argv...>
Run argv in its own app unit once the VPN tunnel reports connected." "$@"

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
  local states listener status=0
  exec {states}< <(exec mullvad status listen 2>/dev/null)
  listener=$!
  timeout "$1" grep -qm1 '^Connected' <&"${states}" || status=$?
  kill "${listener}" 2>/dev/null || true
  exec {states}<&-
  return "${status}"
}

launch_on_workspace() {
  local target="$1"
  shift
  local joined=""
  printf -v joined '%q ' "$@"
  joined="${joined//\\/\\\\}"
  joined="${joined//\'/\\\'}"
  # The exec rule reaches the window through HL_EXEC_RULE_TOKEN, which only a scope inherits; a service unit would drop it.
  hyprctl dispatch "(function() return hl.dsp.exec_cmd('[workspace ${target} silent] hyprshell app -- ${joined}') end)()" >/dev/null
}

command -v mullvad >/dev/null 2>&1 && command -v "$1" >/dev/null 2>&1 || exit 0

# The mullvad daemon and the tunnel both come up after the compositor.
if ! hypr_wait_for_path "${timeout}" "${MULLVAD_RPC_SOCKET_PATH:-/run/mullvad-vpn}" \
  || ((SECONDS >= timeout)) || ! tunnel_connected "$((timeout - SECONDS))"; then
  print_log -sec "startup" -warn "start-if-vpn" "tunnel not connected after ${timeout}s; skipping ${1}"
  exit 0
fi

if [[ -n "${workspace}" ]]; then
  launch_on_workspace "${workspace}" "$@"
  exit 0
fi

exec hyprshell app -- "$@"
