#!/usr/bin/env bash

# Script discovery and execution helpers for hyprshell.

run_lib_script() {
  local rel_path="$1"
  shift

  local script_path="${LIB_DIR}/hypr/${rel_path}"
  if [[ ! -f "${script_path}" ]]; then
    echo "Missing script: ${script_path}" >&2
    return 1
  fi

  "${script_path}" "$@"
}

collect_script_dirs() {
  local scripts_path="${1:-${HYPR_SCRIPTS_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts:${LIB_DIR}/hypr}}"
  IFS=':' read -ra RAW_DIRS <<<"${scripts_path}"

  declare -A seen_dirs=()
  SCRIPT_DIRS=()

  local dir
  for dir in "${RAW_DIRS[@]}"; do
    [[ -z "${dir}" ]] && continue
    [[ -n "${seen_dirs[${dir}]:-}" ]] && continue
    seen_dirs["${dir}"]=1
    [[ -d "${dir}" ]] && SCRIPT_DIRS+=("${dir}")
  done
}

list_script() {
  collect_script_dirs

  local dir
  for dir in "${SCRIPT_DIRS[@]}"; do
    find -L "${dir}" -maxdepth 2 -type f \( -name "*.sh" -o -name "*.py" \) -exec basename {} \; 2>/dev/null
  done | sort -u
}

list_script_path() {
  find -L "${LIB_DIR}/hypr" -type f \( -name "*.sh" -o -name "*.py" \) -print
}

exec_script_target() {
  local base_path="$1"
  shift

  if [[ -f "${base_path}.sh" ]]; then
    exec bash "${base_path}.sh" "$@"
  elif [[ -f "${base_path}.py" ]]; then
    python_activate
    exec python "${base_path}.py" "$@"
  elif [[ -f "${base_path}" && -x "${base_path}" ]]; then
    exec "${base_path}" "$@"
  fi

  return 1
}

run_command() {
  local command_name="$1"
  shift

  collect_script_dirs

  local dir
  for dir in "${SCRIPT_DIRS[@]}"; do
    exec_script_target "${dir}/${command_name}" "$@" && return 0

    local subdir
    for subdir in "${dir}"/*/; do
      [[ -d "${subdir}" ]] || continue
      exec_script_target "${subdir%/}/${command_name}" "$@" && return 0
    done
  done

  if [[ -f "${command_name}" && -x "${command_name}" ]]; then
    exec "${command_name}" "$@"
  fi

  echo "Command not found: ${command_name}"
  echo "Available commands:"
  list_script

  for dir in "${SCRIPT_DIRS[@]}"; do
    echo "Scripts in ${dir}:"
    find -L "${dir}" -maxdepth 2 -type f \( -name "*.sh" -o -name "*.py" -o -executable \) -exec basename {} \; 2>/dev/null | sort -u
  done

  return 1
}
