#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
refresh_hypr_instance_signature
export HYPRLAND_INSTANCE_SIGNATURE
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/window/stateful-choice.common.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/util/workflow.presentation.bash"

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

current_bar_edge() {
  PYTHONPATH="${HYPR_LIB_DIR}" python3 -c 'from pyutils.bar_position import bar_position; print(bar_position())'
}

bar_layout_on_current_edge() {
  PYTHONPATH="${HYPR_LIB_DIR}" python3 - "$@" <<'PY'
import sys
from pyutils.bar_position import bar_position
edge = bar_position()
print(next((layout for layout in sys.argv[1:] if bar_position(layout) == edge), sys.argv[1]))
PY
}

apply_quickshell_workflow() {
  local current_layout_name saved_layout target_layout=""
  local last_applied allowed

  read -ra allowed <<<"$(get_workflow_quickshell_layout "${current_workflow_path}")"
  current_layout_name="$(state_get "QUICKSHELL_LAYOUT_NAME" "top")"
  saved_layout="$(state_get "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "")"
  last_applied="$(state_get "WORKFLOW_QUICKSHELL_LAST_APPLIED_LAYOUT" "")"

  if ((${#allowed[@]})); then
    if [[ "${workflow_previous_name}" != "${current_workflow}" && " ${allowed[*]} " != *" ${current_layout_name} "* ]]; then
      target_layout="$(bar_layout_on_current_edge "${allowed[@]}")"
      [[ -z "${saved_layout}" ]] && state_set "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "${current_layout_name}" "staterc"
    fi
  elif [[ -n "${saved_layout}" ]]; then
    state_set "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "" "staterc"
    if [[ -z "${last_applied}" || "${current_layout_name}" == "${last_applied}" ]]; then
      target_layout="$(bar_layout_on_current_edge "${saved_layout}" top bottom)"
      [[ "${target_layout}" == "${current_layout_name}" ]] && target_layout=""
    fi
  fi

  [[ -n "${target_layout}" ]] || return 0
  if [[ "${target_layout}" == winbar ]]; then
    quickshell ipc call bar winbarEdge "$(current_bar_edge)" >/dev/null 2>&1 || true
  fi
  state_set "WORKFLOW_QUICKSHELL_LAST_APPLIED_LAYOUT" "${target_layout}" "staterc"
  state_set "QUICKSHELL_LAYOUT_NAME" "${target_layout}" "staterc"
  hyprshell render/dunst.py >/dev/null 2>&1 || true
}

sync_workflow_flags() {
  state_set WORKFLOW_WINDOW_LAYOUT "$(sed -n 's/^[[:space:]]*runtime\.config("general\.layout",[[:space:]]*"\([^"]*\)").*/\1/p' "${current_workflow_path}" | head -n1)" staterc
  state_set WORKFLOW_QUICKSHELL_LAYOUT "$(get_workflow_quickshell_layout "${current_workflow_path}")" staterc
}

get_workflow_quickshell_layout() {
  local workflow_path="$1"
  sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_QUICKSHELL_LAYOUT",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1
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
  send_ephemeral_notif "hypr-workflow" -t "${NOTIFY_BRIEF_MS}" -i "preferences-desktop-display" "Workflow" "${current_icon} ${current_workflow}\n${current_description}"
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

LONG_OPTS="set:,reconcile,list,bar,help"
SHORT_OPTS="h"
PARSED=$(getopt --options "${SHORT_OPTS}" --longoptions "${LONG_OPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

while true; do
  case "$1" in
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
