#!/usr/bin/env bash

set -euo pipefail

HYPR_LIB_ROOT="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB_ROOT}/launch/window.common.bash" || exit 1
launch_source_core_common || exit 1

hypr_help_guard "Usage: hyprshell window/apply-profile PROFILE [ADDRESS] [MONITOR]
Resize and center a floating window using a shared geometry profile." "$@"

profile="${1:-}"
window_address="${2:-}"
monitor_selector="${3:-}"

[[ -n "${profile}" ]] || {
  printf 'Missing window profile\n' >&2
  exit 2
}

if [[ -z "${window_address}" ]]; then
  window_address="$(hyprctl activewindow -j | jq -r '.address // empty')"
fi

[[ -n "${window_address}" ]] || {
  printf 'No target window\n' >&2
  exit 1
}

window_address="${window_address#address:}"

if [[ -z "${monitor_selector}" ]]; then
  monitor_selector="$(
    hyprctl clients -j \
      | jq -r --arg address "${window_address}" '.[] | select(.address == $address) | .monitor' \
      | head -n1
  )"
fi

[[ -n "${monitor_selector}" ]] || {
  printf 'Could not resolve the target monitor\n' >&2
  exit 1
}

target_width=""
target_height=""
window_lua=""

IFS=$'\t' read -r target_width target_height \
  <<<"$(launch_resolve_geometry_profile "${profile}" "${monitor_selector}")"
window_lua="$(hypr_lua_quote "address:${window_address}")"

hypr_lua_batch \
  "hl.dsp.window.resize({x=${target_width}, y=${target_height}, exact=true, window=${window_lua}})" \
  "hl.dsp.window.center({window=${window_lua}, respect_reserved=true})"
