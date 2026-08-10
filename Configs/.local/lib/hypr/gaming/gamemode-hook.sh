#!/usr/bin/env bash
set -u

action="${1:-}"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1

state_dir="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/gaming"
previous_file="${state_dir}/gamemode-previous-workflow"
workflows_script="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/util/workflows.sh"
mkdir -p "${state_dir}" || exit 1
exec {lock_fd}>"${state_dir}/gamemode-hook.lock" || exit 1
flock "${lock_fd}" || exit 1

workflow_set() {
  [[ -x "${workflows_script}" ]] && "${workflows_script}" --set "$1" >/dev/null 2>&1
}

case "${action}" in
  start)
    current_workflow="$(state_get HYPR_WORKFLOW "default" 2>/dev/null || printf 'default\n')"
    if [[ "${current_workflow}" != "gaming" ]]; then
      printf '%s\n' "${current_workflow}" >"${previous_file}"
      workflow_set gaming || exit 1
    fi
    ;;
  end)
    if [[ -s "${previous_file}" ]]; then
      read -r previous_workflow <"${previous_file}" || previous_workflow=default
      [[ -n "${previous_workflow}" ]] || previous_workflow=default
      workflow_set "${previous_workflow}" && rm -f "${previous_file}"
    fi
    ;;
  *)
    exit 2
    ;;
esac
