#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

focusmode_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/focusmode.conf"
workflows_script="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/util/workflows.sh"

show_help() {
  cat <<'HELP'
Usage: workflow-toggle.sh focus

Toggle the focus workflow on or off. The gaming workflow is managed by GameMode.
HELP
}

main() {
  local requested_mode="${1:-}"
  local current_workflow target_workflow

  case "${requested_mode}" in
    focus) ;;
    -h | --help)
      show_help
      return 0
      ;;
    *)
      printf 'Usage error: expected focus; gaming is automatic\n' >&2
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
    rm -f "${focusmode_state_file}"
  fi
}

main "$@"
