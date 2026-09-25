#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
refresh_hypr_instance_signature
export HYPRLAND_INSTANCE_SIGNATURE
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/window/stateful-choice.common.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/util/workflow.presentation.bash"

workflows_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/workflows"
workflows_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/workflows"
workflows_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/workflows.lua"
workflow_previous_name="$(state_get "HYPR_WORKFLOW" "default")"

workflow_locked() {
  local owner=""
  [[ "${HYPR_WORKFLOW_UNLOCK:-0}" == 1 ]] && return 1
  hypr_gamemode_active && owner=gaming
  [[ -z "${owner}" && "${HYPR_PROFILE_WORKFLOW_LOCK:-1}" != 0 && "$(hypr_power_profile)" == power-saver ]] && owner=powersaver
  [[ -n "${owner}" && "${1:-}" != "${owner}" ]]
}

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]
Switch the active workflow profile, or report the one the bar should show.

Options:
    --select | -S       Select a workflow from the available options
    --set               Set the given workflow
    --reconcile         Restore the active workflow's runtime side effects
    --list              List selectable workflows as name, icon and description
    --bar               Get workflow info for the active bar
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

apply_quickshell_workflow() {
  local layout current_layout_name saved_layout target_layout=""
  local last_applied

  layout="$(get_workflow_quickshell_layout "${current_workflow_path}")"
  current_layout_name="$(state_get "QUICKSHELL_LAYOUT_NAME" "sidebar")"
  saved_layout="$(state_get "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "")"
  last_applied="$(state_get "WORKFLOW_QUICKSHELL_LAST_APPLIED_LAYOUT" "")"

  if [[ -n "${layout}" ]]; then
    if [[ "${workflow_previous_name}" != "${current_workflow}" ]]; then
      [[ "${current_layout_name}" != "${layout}" ]] && target_layout="${layout}"
      [[ -n "${target_layout}" && -z "${saved_layout}" ]] && state_set "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "${current_layout_name}" "staterc"
    fi
  elif [[ -n "${saved_layout}" ]]; then
    state_set "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "" "staterc"
    if [[ -z "${last_applied}" || "${current_layout_name}" == "${last_applied}" ]]; then
      [[ "${current_layout_name}" != "${saved_layout}" ]] && target_layout="${saved_layout}"
    fi
  fi

  [[ -n "${target_layout}" ]] || return 0
  state_set "WORKFLOW_QUICKSHELL_LAST_APPLIED_LAYOUT" "${target_layout}" "staterc"
  state_set "QUICKSHELL_LAYOUT_NAME" "${target_layout}" "staterc"
  hyprshell render/dunst.py >/dev/null 2>&1 || true
}

sync_workflow_flags() {
  local windows=0 gaming=0
  [[ "${current_workflow}" == windows ]] && windows=1
  [[ "${current_workflow}" == gaming ]] && gaming=1
  state_set HYPR_FOCUSMODE "${windows}" staterc
  state_set HYPR_GAMEMODE "${gaming}" staterc
}

get_workflow_quickshell_layout() {
  local workflow_path="$1"
  sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_QUICKSHELL_LAYOUT",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1
}

select_workflow() {
  local default_path default_icon workflow_list workflow_path workflow_name workflow_icon
  local selected_workflow
  local workflow_count=1
  local max_lines=11
  local menu_lines=0

  hypr_runtime_require rofi
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"

  default_path="$(resolve_workflow_path default)" || {
    dunstify -t 3000 -i "preferences-desktop-display" "Error" "Default workflow not found in ${workflows_user_dir} or ${workflows_shared_dir}"
    exit 1
  }
  default_icon="$(get_workflow_icon "${default_path}")"
  workflow_list="${default_icon}\t default"

  while IFS= read -r workflow_name; do
    [[ "${workflow_name}" == "default" || "${workflow_name}" == "gaming" || "${workflow_name}" == "powersaver" ]] && continue
    workflow_path="$(resolve_workflow_path "${workflow_name}")" || continue
    workflow_icon="$(get_workflow_icon "${workflow_path}")"
    workflow_list="${workflow_list}\n${workflow_icon}\t ${workflow_name}"
    workflow_count=$((workflow_count + 1))
  done < <(list_workflow_names)

  menu_lines=$((workflow_count < max_lines ? workflow_count : max_lines))

  # 2em per row plus 8em of chrome, matching the clipboard picker it shares a theme with
  HYPR_STATEFUL_CHOICE_WIDTH_EM=24 \
    HYPR_STATEFUL_CHOICE_HEIGHT_EM=$((2 * menu_lines + 8)) \
    hypr_stateful_choice_select \
    "Select workflow" \
    " Workflow" \
    "clipboard" \
    "${ROFI_WORKFLOW_SCALE:-}" \
    "${ROFI_WORKFLOW_FONT:-${ROFI_FONT:-}}" \
    "${workflow_previous_name}" \
    "$(printf '%b' "${workflow_list}")" \
    selected_workflow \
    -theme-str "listview { lines: ${menu_lines}; }"

  [[ -n "${selected_workflow}" ]] || exit 0

  selected_workflow=$(awk -F'\t' '{print $2}' <<<"${selected_workflow}" | xargs)
  state_set "HYPR_WORKFLOW" "${selected_workflow}" "staterc"
}

handle_list() {
  local name path
  while IFS= read -r name; do
    [[ "${name}" =~ ^(gaming|powersaver)$ ]] && continue
    path="$(resolve_workflow_path "${name}")" || continue
    printf '%s\t%s\t%s\n' "${name}" "$(get_workflow_icon "${path}")" "$(get_workflow_description "${path}")"
  done < <(list_workflow_names)
}

get_info() {
  local workflow_path

  current_workflow="$(state_get "HYPR_WORKFLOW" "default")"

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

write_workflow_state() {
  hypr_stateful_choice_write_lua "${workflows_state_file}" \
    --load "${current_workflow_path}" \
    "WORKFLOW=${current_workflow}" \
    "WORKFLOW_ICON=${current_icon}" \
    "WORKFLOW_DESCRIPTION=${current_description}" \
    "WORKFLOW_PATH=${current_workflow_path}"

  printf "%s %s: %s\n" "${current_icon}" "${current_workflow}" "${current_description}"
  send_ephemeral_notif "hypr-workflow" -t 2000 -i "preferences-desktop-display" "Workflow" "${current_icon} ${current_workflow}\n${current_description}"
}

apply_workflow_update() {
  local notification_rule notification_state
  get_info
  for notification_rule in windows_90 gaming_opaque powersaver_opaque; do
    [[ "${current_workflow}" == "${notification_rule%%_*}" ]] && notification_state=enable || notification_state=disable
    dunstctl rule "${notification_rule}" "${notification_state}" >/dev/null 2>&1 || true
  done
  if [[ "${workflow_previous_name}" == presentation && "${current_workflow}" != presentation ]]; then
    restore_presentation_side_effects
  fi
  write_workflow_state
  sync_workflow_flags
  hyprctl reload config-only -q
  apply_quickshell_workflow
  if [[ "${workflow_previous_name}" != presentation && "${current_workflow}" == presentation ]]; then
    apply_presentation_side_effects
  fi
}

handle_bar() {
  get_info
  printf '{"text": "%s", "class": "custom-workflows"}\n' "${current_icon}"
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
  exit 1
fi

LONG_OPTS="select,set:,reconcile,list,bar,help"
SHORT_OPTS="Sh"
PARSED=$(getopt --options "${SHORT_OPTS}" --longoptions "${LONG_OPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

while true; do
  case "$1" in
    -S | --select)
      workflow_locked && exit 1
      select_workflow
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
      workflow_locked "$2" && exit 1
      state_set "HYPR_WORKFLOW" "$2" "staterc"
      apply_workflow_update
      exit 0
      ;;
    --reconcile)
      reconcile_workflow_side_effects
      exit 0
      ;;
    --help | -h)
      show_help
      exit 0
      ;;
    --bar)
      handle_bar
      exit 0
      ;;
    --list)
      handle_list
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
