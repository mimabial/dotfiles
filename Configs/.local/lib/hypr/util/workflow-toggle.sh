#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

focusmode_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/focusmode.conf"
gamemode_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/gamemode.conf"
workflows_script="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/util/workflows.sh"

show_help() {
  cat <<'HELP'
Usage: workflow-toggle.sh <focus|gaming>

Toggle the requested workflow on, or switch back to default if it is already active.
HELP
}

sync_workflow_flags() {
  local active_mode="${1:-default}"

  case "${active_mode}" in
    focus)
      state_set "HYPR_FOCUSMODE" "1" "staterc"
      state_set "HYPR_GAMEMODE" "0" "staterc"
      ;;
    gaming)
      state_set "HYPR_FOCUSMODE" "0" "staterc"
      state_set "HYPR_GAMEMODE" "1" "staterc"
      ;;
    *)
      state_set "HYPR_FOCUSMODE" "0" "staterc"
      state_set "HYPR_GAMEMODE" "0" "staterc"
      ;;
  esac
}

main() {
  local requested_mode="${1:-}"
  local current_workflow target_workflow

  case "${requested_mode}" in
    focus | gaming) ;;
    -h | --help)
      show_help
      return 0
      ;;
    *)
      printf 'Usage error: expected focus or gaming\n' >&2
      show_help >&2
      return 1
      ;;
  esac

  current_workflow="$(state_get HYPR_WORKFLOW "default")"
  target_workflow="${requested_mode}"

  if [[ "${current_workflow}" == "${requested_mode}" ]]; then
    target_workflow="default"
  fi

  if "${workflows_script}" --set "${target_workflow}"; then
    rm -f "${focusmode_state_file}" "${gamemode_state_file}"
    sync_workflow_flags "${target_workflow}"
  fi
}

main "$@"
