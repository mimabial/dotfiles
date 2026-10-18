#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/window/lib/visual-presets.bash"

workflow_previous_name="$(state_get "HYPR_WORKFLOW" "default")"

source "${BASH_SOURCE[0]%/*}/workflows/catalog.bash"

workflow_usage() {
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

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  workflow_usage
  exit 1
fi

workflow_long_options="set:,reconcile,list,bar,help"
workflow_short_options="h"
workflow_parsed_arguments=$(getopt --options "${workflow_short_options}" --longoptions "${workflow_long_options}" --name "$0" -- "$@") || exit 2
eval set -- "${workflow_parsed_arguments}"

while true; do
  case "$1" in
    --set)
      workflow_name="${2:-}"
      workflow_name="${workflow_name%.lua}"
      [[ -n "${workflow_name}" ]] || {
        echo "Error: --set requires a workflow name"
        exit 1
      }
      if ! workflow_exists "${workflow_name}"; then
        echo "Error: unknown workflow '$2'" >&2
        exit 1
      fi
      workflow_locked "${workflow_name}" && exit 1
      exec {workflow_lock_fd}>"$(hypr_lock_path_ensure_parent workflow)"
      flock "${workflow_lock_fd}"
      trap 'flock -u "${workflow_lock_fd}"' EXIT
      workflow_previous_name="$(state_get HYPR_WORKFLOW default)"
      workflow_previous_layout_changed="$(state_get WORKFLOW_LAYOUT_CHANGED)"
      workflow_previous_theme_override="$(state_get WORKFLOW_THEME_OVERRIDE)"
      export HYPR_WORKFLOW_TRANSITION=1
      source "${BASH_SOURCE[0]%/*}/workflows/windows.bash"
      if [[ "${workflow_name}" == windows && "${workflow_previous_name}" != windows ]]; then windows_enter || exit 1; fi
      if [[ "${workflow_name}" != "${workflow_previous_name}" && "${workflow_name}" != gaming && "${workflow_previous_name}" != gaming ]]; then
        state_set WORKFLOW_LAYOUT_OVERRIDE "" staterc
        state_set WORKFLOW_LAYOUT_CHANGED "" staterc
        state_set WORKFLOW_THEME_OVERRIDE "" staterc
      fi
      state_set "HYPR_WORKFLOW" "${workflow_name}" "staterc"
      source "${BASH_SOURCE[0]%/*}/workflows/bar-layout.bash"
      # shellcheck source=/dev/null
      source "${BASH_SOURCE[0]%/*}/workflows/presentation.bash"
      source "${BASH_SOURCE[0]%/*}/workflows/selection.bash"
      refresh_hypr_instance_signature
      export HYPRLAND_INSTANCE_SIGNATURE
      workflow_apply_selection
      exit 0
      ;;
    --reconcile)
      source "${BASH_SOURCE[0]%/*}/workflows/presentation.bash"
      reconcile_workflow_side_effects
      exit 0
      ;;
    --help | -h)
      workflow_usage
      exit 0
      ;;
    --bar)
      workflow_emit_bar_status
      exit 0
      ;;
    --list)
      workflow_list_choices
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option: $1"
      workflow_usage
      exit 1
      ;;
  esac
done
