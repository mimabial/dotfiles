#!/usr/bin/env bash

# Toggle to pop-out a tile to stay fixed on a display basis.

set -euo pipefail

HYPR_LIB_ROOT="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB_ROOT}/launch/window.common.bash" || exit 1
launch_source_core_common || exit 1

hypr_help_guard "Usage: hyprshell window/windowpin
Toggle pinning the active window as a centred floating pop-out." "$@"

resolve_active_window() {
  hyprctl activewindow -j
}

unpin_window() {
  local addr="$1"
  local window_lua=""

  window_lua="$(hypr_lua_quote "address:${addr}")"

  hypr_lua_batch \
    "hl.dsp.window.pin({window=${window_lua}, action=\"toggle\"})" \
    "hl.dsp.window.float({window=${window_lua}, action=\"toggle\"})" \
    "hl.dsp.window.tag({window=${window_lua}, tag=\"-pop\"})"
}

pin_window() {
  local addr="$1"
  local pip_width=1
  local pip_height=1
  local window_lua=""

  IFS=$'\t' read -r pip_width pip_height <<<"$(launch_resolve_geometry_profile standard)" || return 1
  window_lua="$(hypr_lua_quote "address:${addr}")"

  hypr_lua_batch \
    "hl.dsp.window.float({window=${window_lua}, action=\"toggle\"})" \
    "hl.dsp.window.resize({x=${pip_width}, y=${pip_height}, exact=true, window=${window_lua}})" \
    "hl.dsp.window.center({window=${window_lua}, respect_reserved=true})" \
    "hl.dsp.window.pin({window=${window_lua}, action=\"toggle\"})" \
    "hl.dsp.window.alter_zorder({window=${window_lua}, mode=\"top\"})" \
    "hl.dsp.window.tag({window=${window_lua}, tag=\"+pop\"})"
}

main() {
  local active=""
  local pinned=""
  local addr=""

  active="$(resolve_active_window)"
  pinned="$(jq '.pinned' <<<"${active}")"
  addr="$(jq -r '.address' <<<"${active}")"

  [ -z "${addr}" ] && {
    echo "No active window"
    return 0
  }

  if [ "${pinned}" = "true" ]; then
    unpin_window "${addr}"
  else
    pin_window "${addr}"
  fi
}

main "$@"
