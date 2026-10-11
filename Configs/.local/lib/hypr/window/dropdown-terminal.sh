#!/usr/bin/env bash

set -euo pipefail

HYPR_LIB_ROOT="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB_ROOT}/launch/lib/window-launch.bash" || exit 1
launch_source_core_common || exit 1

hypr_help_guard "Usage: hyprshell window/dropdown-terminal
Toggle the dropdown terminal: spawn it, or show/hide it on the focused workspace." "$@"

DROPDOWN_WORKSPACE="special:dropdown"

dropdown_target_size() {
  launch_resolve_geometry_profile compact
}

show_dropdown_window() {
  local window_address="$1"
  local workspace_name="$2"
  local window_lua=""
  local workspace_lua=""
  local target_width=""
  local target_height=""
  local target_size=""

  [[ -n "${workspace_name}" ]] || return 1
  target_size="$(dropdown_target_size)" || return 1
  IFS=$'\t' read -r target_width target_height <<<"${target_size}"
  window_lua="$(hypr_lua_quote "address:${window_address}")"
  workspace_lua="$(hypr_lua_quote "${workspace_name}")"

  hypr_lua_batch \
    "hl.dsp.window.move({workspace=${workspace_lua}, window=${window_lua}, silent=true})" \
    "hl.dsp.window.resize({x=${target_width}, y=${target_height}, exact=true, window=${window_lua}})" \
    "hl.dsp.window.center({window=${window_lua}})" \
    "hl.dsp.focus({window=${window_lua}})" \
    >/dev/null 2>&1 || return 1
}

hide_dropdown_window() {
  local window_lua=""
  local workspace_lua=""

  window_lua="$(hypr_lua_quote "address:$1")"
  workspace_lua="$(hypr_lua_quote "${DROPDOWN_WORKSPACE}")"

  hypr_lua_dispatch "hl.dsp.window.move({workspace=${workspace_lua}, window=${window_lua}, silent=true})" \
    >/dev/null 2>&1 || return 1
}

spawn_dropdown_window() {
  local cwd=""

  cwd="$("${HYPR_LIB_ROOT}/launch/terminal-cwd.sh")"
  setsid "${HYPR_LIB_ROOT}/system/app2unit.sh" -- tui-terminal-exec \
    --hypr-profile compact \
    --app-id dropdown-terminal \
    --title "Dropdown Terminal" \
    -- bash -lc 'cd "$1" && exec "${SHELL:-/bin/bash}" -l' bash "${cwd}" \
    >/dev/null 2>&1 &
}

main() {
  local window_address=""
  local window_workspace=""
  local current_workspace=""

  {
    IFS= read -r window_address
    IFS= read -r window_workspace
    IFS= read -r current_workspace
    IFS= read -r HYPR_MONITORS_JSON_CACHE
  } < <(hyprctl --batch -j 'clients;activeworkspace;monitors all' 2>/dev/null | jq -sr '
    (first(.[0][] | select(.class == "dropdown-terminal")) // {}) as $window
    | $window.address // "", $window.workspace.name // "", .[1].name // "", (.[2] // [] | tojson)')
  HYPR_MONITORS_JSON_CACHE_READY=1
  if [[ -z "${window_address}" ]]; then
    spawn_dropdown_window
    return 0
  fi

  if [[ "${window_workspace}" == "${DROPDOWN_WORKSPACE}" ]]; then
    show_dropdown_window "${window_address}" "${current_workspace}"
    return 0
  fi

  if [[ -n "${current_workspace}" && "${window_workspace}" == "${current_workspace}" ]]; then
    hide_dropdown_window "${window_address}"
    return 0
  fi

  show_dropdown_window "${window_address}" "${current_workspace}"
}

main "$@"
