#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
if ! source "$(command -v hyprshell)"; then
  echo "[$0] :: Error: hyprshell not found."
  exit 1
fi
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/window/stateful-choice.common.bash"

workflows_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/workflows"
workflows_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/workflows"
workflows_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/workflows.lua"
workflow_previous_name="$(state_get "HYPR_WORKFLOW" "default")"

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]

Options:
    --select | -S       Select a workflow from the available options
    --set               Set the given workflow
    --waybar            Get workflow info for Waybar
    --help   | -h       Show this help message
HELP
}

resolve_workflow_path() {
  local name="${1:-default}"
  name="${name%.lua}"
  hypr_stateful_choice_resolve_path "${name}" "lua" "${workflows_user_dir}" "${workflows_shared_dir}"
}

workflow_exists() {
  local name="${1:-}"
  [[ -n "${name}" ]] || return 1
  resolve_workflow_path "${name}" >/dev/null 2>&1
}

list_workflow_names() {
  hypr_stateful_choice_list_names "lua" "${workflows_user_dir}" "${workflows_shared_dir}"
}

get_workflow_icon() {
  local workflow_path="$1"
  local workflow_icon
  workflow_icon="$(sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_ICON",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1)"
  printf '%s\n' "${workflow_icon:0:1}"
}

get_workflow_description() {
  local workflow_path="$1"
  local description
  description="$(sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_DESCRIPTION",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1)"
  printf '%s\n' "${description:-No description available}"
}

get_workflow_waybar_mode() {
  local workflow_path="$1"
  sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_WAYBAR",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1
}

get_workflow_waybar_opacity() {
  local workflow_path="$1"
  sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_WAYBAR_OPACITY",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1
}

apply_waybar_workflow() {
  local mode css="" signal="RTMIN+7"
  local workflow_css_file="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/includes/workflow.css"
  local layout current_layout_name saved_layout target_layout=""
  local rounding opacity last_applied

  mode="$(get_workflow_waybar_mode "${current_workflow_path}")"
  opacity="$(get_workflow_waybar_opacity "${current_workflow_path}")"
  layout="$(get_workflow_waybar_layout "${current_workflow_path}")"
  current_layout_name="$(state_get "WAYBAR_LAYOUT_NAME" "")"
  saved_layout="$(state_get "WORKFLOW_WAYBAR_PREV_LAYOUT" "")"
  last_applied="$(state_get "WORKFLOW_WAYBAR_LAST_APPLIED_LAYOUT" "")"
  rounding="$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r '.int // empty')"

  if [[ -n "${layout}" ]]; then
    if [[ "${workflow_previous_name}" != "${current_workflow}" ]]; then
      [[ "${current_layout_name}" != "${layout}" ]] && target_layout="${layout}"
      [[ -n "${target_layout}" && -z "${saved_layout}" ]] && state_set "WORKFLOW_WAYBAR_PREV_LAYOUT" "${current_layout_name}" "staterc"
    fi
  elif [[ -n "${saved_layout}" ]]; then
    state_set "WORKFLOW_WAYBAR_PREV_LAYOUT" "" "staterc"
    if [[ -z "${last_applied}" || "${current_layout_name}" == "${last_applied}" ]]; then
      [[ "${current_layout_name}" != "${saved_layout}" ]] && target_layout="${saved_layout}"
    fi
  fi

  [[ -n "${target_layout}" ]] && state_set "WORKFLOW_WAYBAR_LAST_APPLIED_LAYOUT" "${target_layout}" "staterc"

  if [[ "${mode}" == "hidden" ]]; then
    [[ -n "${target_layout}" ]] && WAYBAR_BORDER_RADIUS="${rounding}" hyprshell waybar.py --set "${target_layout}" --no-restart >/dev/null 2>&1
    hyprshell waybar.py --kill >/dev/null 2>&1 || true
    return 0
  fi

  [[ "${opacity}" =~ ^[0-9]*\.?[0-9]+$ ]] && css="window#waybar { background: alpha(@bg, ${opacity}); }"
  if [[ "$(cat "${workflow_css_file}" 2>/dev/null)" != "${css}" ]]; then
    printf '%s\n' "${css}" >"${workflow_css_file}"
    signal="SIGUSR2"
  fi

  if [[ -n "${target_layout}" ]]; then
    WAYBAR_BORDER_RADIUS="${rounding}" hyprshell waybar.py --set "${target_layout}" >/dev/null 2>&1 || true
    return 0
  fi

  WAYBAR_BORDER_RADIUS="${rounding}" hyprshell waybar.py --update-border-radius >/dev/null 2>&1 || true

  # A freshly started waybar must not be signaled: real-time signals arriving
  # before its handlers are installed terminate it.
  if hypr_user_pgrep -x waybar >/dev/null; then
    hypr_user_pkill "-${signal}" -x waybar >/dev/null 2>&1 || true
  else
    hyprshell waybar.py --restart-direct >/dev/null 2>&1 || true
  fi
}

get_workflow_power_profile() {
  local workflow_path="$1"
  sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_POWER_PROFILE",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1
}

apply_power_profile_workflow() {
  local profile current_profile saved_profile
  command -v powerprofilesctl >/dev/null 2>&1 || return 0

  profile="$(get_workflow_power_profile "${current_workflow_path}")"
  saved_profile="$(state_get "WORKFLOW_POWER_PROFILE_PREV" "")"

  if [[ -n "${profile}" ]]; then
    current_profile="$(powerprofilesctl get 2>/dev/null || true)"
    if [[ "${current_profile}" != "${profile}" ]]; then
      [[ -n "${saved_profile}" ]] || state_set "WORKFLOW_POWER_PROFILE_PREV" "${current_profile}" "staterc"
      powerprofilesctl set "${profile}" >/dev/null 2>&1 || true
    fi
  elif [[ -n "${saved_profile}" ]]; then
    state_set "WORKFLOW_POWER_PROFILE_PREV" "" "staterc"
    powerprofilesctl set "${saved_profile}" >/dev/null 2>&1 || true
  fi
}

get_workflow_waybar_layout() {
  local workflow_path="$1"
  sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_WAYBAR_LAYOUT",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1
}

fn_select() {
  local default_path default_icon workflow_list workflow_path workflow_name workflow_icon
  local selected_workflow
  local workflow_count=1
  local clipboard_row_em=2 clipboard_chrome_em=8 clipboard_max_lines=11
  local width_em=24 height_em=0 menu_lines=0
  local font_name="" font_scale=""
  local rofi_position="" window_theme=""
  local -a rofi_args

  default_path="$(resolve_workflow_path default)" || {
    dunstify -t 3000 -i "preferences-desktop-display" "Error" "Default workflow not found in ${workflows_user_dir} or ${workflows_shared_dir}"
    exit 1
  }
  default_icon="$(get_workflow_icon "${default_path}")"
  workflow_list="${default_icon}\t default"

  while IFS= read -r workflow_name; do
    [[ "${workflow_name}" == "default" ]] && continue
    workflow_path="$(resolve_workflow_path "${workflow_name}")" || continue
    workflow_icon="$(get_workflow_icon "${workflow_path}")"
    workflow_list="${workflow_list}\n${workflow_icon}\t ${workflow_name}"
    workflow_count=$((workflow_count + 1))
  done < <(list_workflow_names)

  menu_lines=$((workflow_count < clipboard_max_lines ? workflow_count : clipboard_max_lines))
  height_em=$((clipboard_row_em * menu_lines + clipboard_chrome_em))
  font_scale="$(rofi_effective_font_scale "${ROFI_WORKFLOW_SCALE:-}")"
  font_name="$(rofi_effective_font_name "${ROFI_WORKFLOW_FONT:-${ROFI_FONT:-}}")"

  rofi_picker_compute_window_geometry \
    rofi_position window_theme \
    "${font_name}" "${font_scale}" \
    "${width_em}" "${height_em}" \
    $((width_em * font_scale * 2)) $((height_em * font_scale * 2))

  rofi_build_standard_menu_args \
    rofi_args \
    "Select workflow" \
    " Workflow" \
    "clipboard" \
    "${font_scale}" \
    "${font_name}" \
    wallbox same "${rofi_position}"
  rofi_args+=(-theme-str "${window_theme}")
  rofi_args+=(-theme-str "listview { lines: ${menu_lines}; }")
  rofi_args+=(-select "${HYPR_WORKFLOW:-default}")

  selected_workflow=$(echo -e "${workflow_list}" \
    | rofi "${rofi_args[@]}")

  [[ -n "${selected_workflow}" ]] || exit 0

  selected_workflow=$(awk -F'\t' '{print $2}' <<<"${selected_workflow}" | xargs)
  state_set "HYPR_WORKFLOW" "${selected_workflow}" "staterc"
}

get_info() {
  local workflow_path

  declare -F export_hypr_config >/dev/null && export_hypr_config
  current_workflow=${HYPR_WORKFLOW:-default}

  workflow_path="$(resolve_workflow_path "${current_workflow}" || true)"
  if [[ -z "${workflow_path}" ]]; then
    current_workflow=default
    workflow_path="$(resolve_workflow_path default)"
  fi

  current_icon="$(get_workflow_icon "${workflow_path}")"
  current_description="$(get_workflow_description "${workflow_path}")"
  current_workflow_path="${workflow_path}"
  export current_icon current_workflow current_description current_workflow_path
}

fn_update() {
  local workflow_path_compact
  local workflow_name_lua workflow_icon_lua workflow_description_lua workflow_path_lua

  get_info
  mkdir -p "$(dirname "${workflows_state_file}")"
  workflow_path_compact="$(hypr_compact_path "${current_workflow_path}")"

  workflow_name_lua="$(jq -Rn --arg value "${current_workflow}" '$value')"
  workflow_icon_lua="$(jq -Rn --arg value "${current_icon}" '$value')"
  workflow_description_lua="$(jq -Rn --arg value "${current_description}" '$value')"
  workflow_path_lua="$(jq -Rn --arg value "${current_workflow_path}" '$value')"
  cat <<LUA >"${workflows_state_file}"
-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW", ${workflow_name_lua})
vars.set("WORKFLOW_ICON", ${workflow_icon_lua})
vars.set("WORKFLOW_DESCRIPTION", ${workflow_description_lua})
vars.set("WORKFLOW_PATH", ${workflow_path_lua})
runtime.load(${workflow_path_lua})
LUA

  printf "%s %s: %s\n" "${current_icon}" "${current_workflow}" "${current_description}"
  send_ephemeral_notif "hypr-workflow" -t 2000 -i "preferences-desktop-display" "Workflow" "${current_icon} ${current_workflow}\n${current_description}"
}

apply_workflow_update() {
  fn_update
  hyprctl reload config-only -q
  apply_waybar_workflow
  apply_power_profile_workflow
}

handle_waybar() {
  get_info
  printf '{"text": "%s", "tooltip": "Mode: %s %s \\n%s", "class": "custom-workflows"}\n' \
    "${current_icon}" "${current_icon}" "${current_workflow}" "${current_description}"
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
  exit 1
fi

LONG_OPTS="select,set:,waybar,help"
SHORT_OPTS="Sh"
PARSED=$(getopt --options "${SHORT_OPTS}" --longoptions "${LONG_OPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

while true; do
  case "$1" in
    -S | --select)
      fn_select
      apply_workflow_update
      exit 0
      ;;
    --set)
      [[ -n "${2:-}" ]] || {
        echo "Error: --set requires a workflow name"
        exit 1
      }
      if ! workflow_exists "$2"; then
        echo "Error: unknown workflow '$2'" >&2
        exit 1
      fi
      state_set "HYPR_WORKFLOW" "$2" "staterc"
      apply_workflow_update
      exit 0
      ;;
    --help | -h)
      show_help
      exit 0
      ;;
    --waybar)
      handle_waybar
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option: $1"
      show_help
      exit 1
      ;;
  esac
done
