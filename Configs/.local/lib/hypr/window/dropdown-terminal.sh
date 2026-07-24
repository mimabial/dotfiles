#!/usr/bin/env bash

set -euo pipefail

HYPR_LIB_ROOT="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB_ROOT}/launch/window.common.bash" || exit 1
launch_source_core_common || exit 1

hypr_help_guard "Usage: hyprshell window/dropdown-terminal
Toggle the dropdown terminal: spawn it, or show/hide it on the focused workspace." "$@"

dropdown_workspace_name() {
  printf '%s\n' "special:dropdown"
}

dropdown_client_json() {
  hyprctl clients -j 2>/dev/null \
    | jq -c '.[] | select(.class=="dropdown-terminal")' \
    | head -n1
}

focused_workspace_name() {
  hyprctl activeworkspace -j 2>/dev/null \
    | jq -r '.name // empty'
}

dropdown_target_size() {
  launch_resolve_geometry_profile compact
}

show_dropdown_window() {
  local client_json="$1"
  local addr=""
  local window_lua=""
  local workspace_lua=""
  local target_width=""
  local target_height=""
  local workspace_name=""

  addr="$(jq -r '.address // empty' <<<"${client_json}")"
  [[ -n "${addr}" ]] || return 1
  workspace_name="$(focused_workspace_name)"
  [[ -n "${workspace_name}" ]] || return 1
  IFS=$'\t' read -r target_width target_height <<<"$(dropdown_target_size)" || return 1
  window_lua="$(hypr_lua_quote "address:${addr}")"
  workspace_lua="$(hypr_lua_quote "${workspace_name}")"

  hypr_lua_batch \
    "hl.dsp.window.move({workspace=${workspace_lua}, window=${window_lua}, silent=true})" \
    "hl.dsp.window.resize({x=${target_width}, y=${target_height}, exact=true, window=${window_lua}})" \
    "hl.dsp.window.center({window=${window_lua}})" \
    "hl.dsp.focus({window=${window_lua}})" \
    >/dev/null 2>&1 || return 1
}

hide_dropdown_window() {
  local client_json="$1"
  local addr=""
  local window_lua=""
  local workspace_lua=""

  addr="$(jq -r '.address // empty' <<<"${client_json}")"
  [[ -n "${addr}" ]] || return 1
  window_lua="$(hypr_lua_quote "address:${addr}")"
  workspace_lua="$(hypr_lua_quote "$(dropdown_workspace_name)")"

  hypr_lua_dispatch "hl.dsp.window.move({workspace=${workspace_lua}, window=${window_lua}, silent=true})" \
    >/dev/null 2>&1 || return 1
}

spawn_dropdown_window() {
  local cwd=""

  cwd="$(hyprshell terminal-cwd.sh)"
  setsid uwsm-app -- tui-terminal-exec \
    --hypr-profile compact \
    --app-id dropdown-terminal \
    --title "Dropdown Terminal" \
    -- bash -lc 'cd "$1" && exec "${SHELL:-/bin/bash}" -l' bash "${cwd}" \
    >/dev/null 2>&1 &
}

main() {
  local client_json=""
  local workspace_name=""
  local current_workspace=""

  client_json="$(dropdown_client_json)"
  if [[ -z "${client_json}" ]]; then
    spawn_dropdown_window
    return 0
  fi

  workspace_name="$(jq -r '.workspace.name // empty' <<<"${client_json}")"
  current_workspace="$(focused_workspace_name)"

  if [[ "${workspace_name}" == "$(dropdown_workspace_name)" ]]; then
    show_dropdown_window "${client_json}"
    return 0
  fi

  if [[ -n "${current_workspace}" && "${workspace_name}" == "${current_workspace}" ]]; then
    hide_dropdown_window "${client_json}"
    return 0
  fi

  show_dropdown_window "${client_json}"
}

main "$@"
