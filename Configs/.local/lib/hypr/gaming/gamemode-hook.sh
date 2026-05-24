#!/usr/bin/env bash
set -u

action="${1:-}"
hyprshell_bin="${HOME}/.local/bin/hyprshell"

[[ -r "${hyprshell_bin}" ]] || exit 0
# shellcheck source=/dev/null
source "${hyprshell_bin}" >/dev/null 2>&1 || exit 0

state_dir="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/gaming"
previous_file="${state_dir}/gamemode-previous-workflow"
workflows_script="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/util/workflows.sh"

workflow_set() {
  [[ -x "${workflows_script}" ]] || return 0
  "${workflows_script}" --set "$1" >/dev/null 2>&1 || true
}

case "${action}" in
  start)
    mkdir -p "${state_dir}" || exit 0
    current_workflow="$(state_get HYPR_WORKFLOW "default" 2>/dev/null || printf 'default\n')"
    if [[ "${current_workflow}" != "gaming" ]]; then
      printf '%s\n' "${current_workflow}" >"${previous_file}"
      workflow_set gaming
    fi
    ;;
  end)
    if [[ -s "${previous_file}" ]]; then
      read -r previous_workflow <"${previous_file}" || previous_workflow=default
      rm -f "${previous_file}"
      [[ -n "${previous_workflow}" ]] || previous_workflow=default
      workflow_set "${previous_workflow}"
    fi
    ;;
  *)
    exit 2
    ;;
esac
