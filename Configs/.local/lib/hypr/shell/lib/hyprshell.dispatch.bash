#!/usr/bin/env bash

hyprshell_run_library_script() {
  local script_path="${LIB_DIR}/hypr/$1"
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
  local -n candidates_ref="$1" search_roots_ref="$3"
  local command_name="$2" directory subdirectory resolved_path
  candidates_ref=()
  for directory in "${search_roots_ref[@]}"; do
    if hyprshell_resolve_script_path_into resolved_path "${directory}/${command_name}"; then
      candidates_ref+=("${resolved_path}")
    fi
    [[ "${command_name}" == */* ]] && continue
    for subdirectory in "${directory}"/*/; do
      [[ -d "${subdirectory}" ]] || continue
      if hyprshell_resolve_script_path_into resolved_path "${subdirectory%/}/${command_name}"; then
        candidates_ref+=("${resolved_path}")
      fi
    done
  done
}

hyprshell_print_ambiguous_command_error() {
  local command_name="$1" script_path directory
  local -n candidates_ref="$2" search_roots_ref="$3"
  printf 'Ambiguous command: %s\nUse one of:\n' "${command_name}" >&2
  for script_path in "${candidates_ref[@]}"; do
    for directory in "${search_roots_ref[@]}"; do
      if [[ "${script_path}" == "${directory}/"* ]]; then
        script_path="${script_path#"${directory}"/}"
        script_path="${script_path%.sh}"
        script_path="${script_path%.py}"
        break
      fi
    done
    printf '  %s\n' "${script_path}" >&2
  done
}

hyprshell_print_command_path() {
  local command_name="${1:-}" directory direct_script_path
  local -a script_roots=() command_paths=()
  [[ -n "${command_name}" ]] || {
    printf 'Usage: hyprshell resolve <command>\n' >&2
    return 1
  }
  hyprshell_script_roots_into script_roots
  hyprshell_command_paths_into command_paths "${command_name}" script_roots
  if ((${#command_paths[@]} > 1)); then
    hyprshell_print_ambiguous_command_error "${command_name}" command_paths script_roots
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
  for directory in "${script_roots[@]}"; do
    if [[ "${command_paths[0]}" == "${directory}/"* ]]; then
      printf '%s\n' "${command_paths[0]#"${directory}"/}"
      return 0
    fi
  done
  printf '%s\n' "${command_paths[0]}"
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
  local -a script_roots=() command_paths=()
  shift
  hyprshell_script_roots_into script_roots
  hyprshell_command_paths_into command_paths "${command_name}" script_roots
  if ((${#command_paths[@]} == 1)); then
    hyprshell_exec_script "${command_paths[0]}" "$@"
    return $?
  fi
  if ((${#command_paths[@]} > 1)); then
    hyprshell_print_ambiguous_command_error "${command_name}" command_paths script_roots
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
