#!/usr/bin/env bash

hyprshell_run_library_script() {
  local script_path="${HYPR_LIB_DIR}/$1"
  shift
  [[ -f "${script_path}" ]] || {
    printf 'Missing script: %s\n' "${script_path}" >&2
    return 1
  }
  "${script_path}" "$@"
}

hyprshell_resolve_script_path_into() {
  local -n resolved_path_ref="$1"
  local base_path="$2"
  resolved_path_ref=""
  if [[ -f "${base_path}.sh" ]]; then
    resolved_path_ref="${base_path}.sh"
  elif [[ -f "${base_path}.py" ]]; then
    resolved_path_ref="${base_path}.py"
  elif [[ -f "${base_path}" ]]; then
    case "${base_path}" in
      *.sh | *.py) resolved_path_ref="${base_path}" ;;
      *) [[ -x "${base_path}" ]] && resolved_path_ref="${base_path}" ;;
    esac
  fi
  [[ -n "${resolved_path_ref}" ]]
}

hyprshell_command_paths_into() {
  local -n candidates_ref="$1"
  local command_name="$2" subdirectory resolved_path
  candidates_ref=()
  if hyprshell_resolve_script_path_into resolved_path "${HYPR_LIB_DIR}/${command_name}"; then
    candidates_ref+=("${resolved_path}")
  fi
  [[ "${command_name}" == */* ]] && return 0
  for subdirectory in "${HYPR_LIB_DIR}"/*/; do
    [[ -d "${subdirectory}" ]] || continue
    if hyprshell_resolve_script_path_into resolved_path "${subdirectory%/}/${command_name}"; then
      candidates_ref+=("${resolved_path}")
    fi
  done
}

hyprshell_print_ambiguous_command_error() {
  local command_name="$1" script_path
  local -n candidates_ref="$2"
  printf 'Ambiguous command: %s\nUse one of:\n' "${command_name}" >&2
  for script_path in "${candidates_ref[@]}"; do
    script_path="${script_path#"${HYPR_LIB_DIR}"/}"
    script_path="${script_path%.sh}"
    printf '  %s\n' "${script_path%.py}" >&2
  done
}

hyprshell_print_command_path() {
  local command_name="${1:-}" direct_script_path
  local -a command_paths=()
  [[ -n "${command_name}" ]] || {
    printf 'Usage: hyprshell resolve <command>\n' >&2
    return 1
  }
  hyprshell_command_paths_into command_paths "${command_name}"
  if ((${#command_paths[@]} > 1)); then
    hyprshell_print_ambiguous_command_error "${command_name}" command_paths
    return 1
  fi
  if ((${#command_paths[@]} == 0)); then
    if [[ -f "${command_name}" ]] && hyprshell_resolve_script_path_into direct_script_path "${command_name}"; then
      printf '%s\n' "${direct_script_path}"
      return 0
    fi
    printf 'Command not found: %s\n' "${command_name}" >&2
    return 1
  fi
  printf '%s\n' "${command_paths[0]#"${HYPR_LIB_DIR}"/}"
}

hyprshell_exec_script() {
  local script_path="$1"
  shift
  case "${script_path}" in
    *.sh) exec bash "${script_path}" "$@" ;;
    *.py)
      hyprshell_load_venv_helpers || return 1
      hyprshell_ensure_and_activate_python_environment || return 1
      exec python "${script_path}" "$@"
      ;;
    *) exec "${script_path}" "$@" ;;
  esac
}

hyprshell_exec_command() {
  local command_name="$1" direct_script_path
  local -a command_paths=()
  shift
  hyprshell_command_paths_into command_paths "${command_name}"
  if ((${#command_paths[@]} == 1)); then
    hyprshell_exec_script "${command_paths[0]}" "$@"
    return $?
  fi
  if ((${#command_paths[@]} > 1)); then
    hyprshell_print_ambiguous_command_error "${command_name}" command_paths
    return 1
  fi
  if [[ -f "${command_name}" ]] && hyprshell_resolve_script_path_into direct_script_path "${command_name}"; then
    hyprshell_exec_script "${direct_script_path}" "$@"
    return $?
  fi
  {
    printf 'Command not found: %s\nAvailable commands:\n' "${command_name}"
    hyprshell_print_script_names
  } >&2
  return 1
}
