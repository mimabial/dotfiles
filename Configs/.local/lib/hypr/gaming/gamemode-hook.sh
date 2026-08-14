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
  local output=""
  if ! output="$(HYPR_WORKFLOW_UNLOCK=1 "${workflows_script}" --set "$1" 2>&1)"; then
    print_log -sec "gamemode" -err "workflow" "${output:-failed to set $1}"
    return 1
  fi
}

gamemode_active() {
  [[ "$(busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount 2>/dev/null)" =~ ^i[[:space:]]+[1-9][0-9]*$ ]]
}

start_mode() {
  local current
  current="$(state_get HYPR_WORKFLOW default 2>/dev/null || printf 'default\n')"
  if [[ "${current}" == gaming ]]; then
    [[ -s "${previous_file}" ]] || printf 'default\n' >"${previous_file}"
    return
  fi
  printf '%s\n' "${current}" >"${previous_file}"
  workflow_set gaming
}

end_mode() {
  local current previous=default
  current="$(state_get HYPR_WORKFLOW default 2>/dev/null || printf 'default\n')"
  if [[ "${current}" == gaming ]]; then
    [[ ! -s "${previous_file}" ]] || read -r previous <"${previous_file}"
    [[ -n "${previous}" ]] || previous=default
    workflow_set "${previous}" || return
  fi
  rm -f "${previous_file}"
}

case "${action}" in
  start) start_mode ;;
  end) end_mode ;;
  reconcile)
    if gamemode_active; then
      [[ -s "${previous_file}" ]] || start_mode
    else
      end_mode
    fi
    ;;
  *)
    exit 2
    ;;
esac
