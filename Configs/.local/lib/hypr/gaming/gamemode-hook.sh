#!/usr/bin/env bash
set -u

action="${1:-}"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1

state_dir="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/gaming"
previous_workflow_file="${state_dir}/gamemode-previous-workflow"
workflows_script="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/util/workflows.sh"
mkdir -p "${state_dir}" || exit 1
exec {lock_fd}>"${state_dir}/gamemode-hook.lock" || exit 1
flock "${lock_fd}" || exit 1

workflow_set() {
  local output=""
  if ! output="$(HYPR_WORKFLOW_UNLOCK=1 "${workflows_script}" --set "$1" 2>&1)"; then
    print_log -sec "gamemode" -err "workflow" "${output:-failed to set $1}"
    return 1
  fi
}

gamemode_active() {
  [[ "$(busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount 2>/dev/null)" =~ ^i[[:space:]]+[1-9][0-9]*$ ]]
}

enter_gaming_workflow() {
  local current_workflow
  current_workflow="$(state_get HYPR_WORKFLOW default 2>/dev/null || printf 'default\n')"
  if [[ "${current_workflow}" == gaming ]]; then
    [[ -s "${previous_workflow_file}" ]] || printf 'default\n' >"${previous_workflow_file}"
    return
  fi
  printf '%s\n' "${current_workflow}" >"${previous_workflow_file}"
  workflow_set gaming
}

restore_previous_workflow() {
  local current_workflow previous_workflow=default
  current_workflow="$(state_get HYPR_WORKFLOW default 2>/dev/null || printf 'default\n')"
  if [[ "${current_workflow}" == gaming ]]; then
    [[ ! -s "${previous_workflow_file}" ]] || read -r previous_workflow <"${previous_workflow_file}"
    [[ -n "${previous_workflow}" ]] || previous_workflow=default
    workflow_set "${previous_workflow}" || return
  fi
  rm -f "${previous_workflow_file}"
}

case "${action}" in
  start) enter_gaming_workflow ;;
  end) restore_previous_workflow ;;
  reconcile)
    if gamemode_active; then
      [[ -s "${previous_workflow_file}" ]] || enter_gaming_workflow
    else
      restore_previous_workflow
    fi
    ;;
  *)
    exit 2
    ;;
esac
