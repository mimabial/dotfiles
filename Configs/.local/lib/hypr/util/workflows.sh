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

fn_select() {
  local default_path default_icon workflow_list workflow_path workflow_name workflow_icon
  local selected_workflow
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
  done < <(list_workflow_names)

  rofi_build_standard_menu_args \
    rofi_args \
    "Select workflow" \
    " Workflow" \
    "clipboard" \
    "${ROFI_WORKFLOW_SCALE:-}" \
    "${ROFI_WORKFLOW_FONT:-${ROFI_FONT:-}}"
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
  if hypr_user_pgrep -x waybar >/dev/null; then
    hypr_user_pkill -RTMIN+7 -x waybar
  fi
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
