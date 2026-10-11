#!/usr/bin/env bash

set -euo pipefail

HYPR_LIB_ROOT="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB_ROOT}/launch/lib/window-launch.bash" || exit 1
launch_source_core_common || exit 1

hypr_help_guard "Usage: hyprshell window/windowpin
Toggle pinning the active window as a centred floating pop-out." "$@"

resolve_active_window() {
  hyprctl activewindow -j
}

unpin_window() {
  local window_address="$1"
  local window_lua=""

  window_lua="$(hypr_lua_quote "address:${window_address}")"

  hypr_lua_batch \
    "hl.dsp.window.pin({window=${window_lua}, action=\"disable\"})" \
    "hl.dsp.window.float({window=${window_lua}, action=\"disable\"})" \
    "hl.dsp.window.tag({window=${window_lua}, tag=\"-pop\"})"
}

pin_window() {
  local window_address="$1"
  local target_width=1
  local target_height=1
  local target_size=""
  local window_lua=""

  target_size="$(launch_resolve_geometry_profile standard)" || return 1
  IFS=$'\t' read -r target_width target_height <<<"${target_size}"
  window_lua="$(hypr_lua_quote "address:${window_address}")"

  hypr_lua_batch \
    "hl.dsp.window.float({window=${window_lua}, action=\"enable\"})" \
    "hl.dsp.window.resize({x=${target_width}, y=${target_height}, exact=true, window=${window_lua}})" \
    "hl.dsp.window.center({window=${window_lua}, respect_reserved=true})" \
    "hl.dsp.window.pin({window=${window_lua}, action=\"enable\"})" \
    "hl.dsp.window.alter_zorder({window=${window_lua}, mode=\"top\"})" \
    "hl.dsp.window.tag({window=${window_lua}, tag=\"+pop\"})"
}

main() {
  local active=""
  local pinned=""
  local window_address=""

  active="$(resolve_active_window)"
  pinned="$(jq '.pinned' <<<"${active}")"
  window_address="$(jq -r '.address' <<<"${active}")"

  [ -z "${window_address}" ] && {
    echo "No active window"
    return 0
  }

  if [ "${pinned}" = "true" ]; then
    unpin_window "${window_address}"
  else
    pin_window "${window_address}"
  fi
}

main "$@"
