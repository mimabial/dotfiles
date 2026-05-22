#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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

is_internal_script() {
  local rel_path="$1"
  case "${rel_path}" in
    core/* | runtime/* | pyutils/* | shell/lib/* | shell/*) return 0 ;;
    *.lib.sh | *.lib.bash | *.lib.py) return 0 ;;
    *.common.sh | *.common.bash | *.common.py) return 0 ;;
    *_lib.sh | *_lib.bash | *_lib.py) return 0 ;;
    *_common.sh | *_common.bash | *_common.py) return 0 ;;
    *__init__.py) return 0 ;;
  esac
  return 1
}

list_script() {
  collect_script_dirs

  local dir
  local rel_path=""
  while IFS= read -r rel_path; do
    [[ -n "${rel_path}" ]] || continue
    is_internal_script "${rel_path}" && continue
    rel_path="${rel_path%.sh}"
    rel_path="${rel_path%.py}"
    printf '%s\n' "${rel_path}"
  done < <(
    for dir in "${SCRIPT_DIRS[@]}"; do
      find -L "${dir}" -maxdepth 2 -type f \( -name "*.sh" -o -name "*.py" \) -printf '%P\n' 2>/dev/null
    done | sort -u
  )
}

list_script_path() {
  find -L "${LIB_DIR}/hypr" \
    -path '*/__pycache__' -prune -o \
    -type f \( -name "*.sh" -o -name "*.py" \) -print
}

resolve_script_target() {
  local base_path="$1"

  if [[ -f "${base_path}.sh" ]]; then
    printf 'bash\t%s\n' "${base_path}.sh"
  elif [[ -f "${base_path}.py" ]]; then
    printf 'python\t%s\n' "${base_path}.py"
  elif [[ -f "${base_path}" ]]; then
    case "${base_path}" in
      *.sh) printf 'bash\t%s\n' "${base_path}" ;;
      *.py) printf 'python\t%s\n' "${base_path}" ;;
      *)
        [[ -x "${base_path}" ]] && printf 'exec\t%s\n' "${base_path}"
        ;;
    esac
  else
    return 1
  fi
}

exec_resolved_script_target() {
  local target_type="$1"
  local target_path="$2"
  shift 2

  case "${target_type}" in
    bash)
      exec bash "${target_path}" "$@"
      ;;
    python)
      python_activate
      exec python "${target_path}" "$@"
      ;;
    exec)
      exec "${target_path}" "$@"
      ;;
  esac

  return 1
}

append_command_candidate() {
  local base_path="$1"
  local resolved=""

  resolved="$(resolve_script_target "${base_path}")" || return 0
  CANDIDATES+=("${resolved}")
}

resolve_command_candidates() {
  local command_name="$1"
  local dir=""
  local subdir=""

  CANDIDATES=()
  collect_script_dirs

  if [[ "${command_name}" == */* ]]; then
    for dir in "${SCRIPT_DIRS[@]}"; do
      append_command_candidate "${dir}/${command_name}"
    done
    return 0
  fi

  for dir in "${SCRIPT_DIRS[@]}"; do
    append_command_candidate "${dir}/${command_name}"

    for subdir in "${dir}"/*/; do
      [[ -d "${subdir}" ]] || continue
      append_command_candidate "${subdir%/}/${command_name}"
    done
  done
}

print_ambiguous_command_error() {
  local command_name="$1"
  local candidate=""
  local target_path=""

  printf 'Ambiguous command: %s\n' "${command_name}" >&2
  printf 'Use one of:\n' >&2
  for candidate in "${CANDIDATES[@]}"; do
    target_path="${candidate#*$'\t'}"
    for dir in "${SCRIPT_DIRS[@]}"; do
      if [[ "${target_path}" == "${dir}/"* ]]; then
        target_path="${target_path#${dir}/}"
        target_path="${target_path%.sh}"
        target_path="${target_path%.py}"
        break
      fi
    done
    printf '  %s\n' "${target_path}" >&2
  done
}

run_command() {
  local command_name="$1"
  shift

  resolve_command_candidates "${command_name}"

  if ((${#CANDIDATES[@]} == 1)); then
    local target_type="${CANDIDATES[0]%%$'\t'*}"
    local target_path="${CANDIDATES[0]#*$'\t'}"
    exec_resolved_script_target "${target_type}" "${target_path}" "$@"
    return 0
  fi

  if ((${#CANDIDATES[@]} > 1)); then
    print_ambiguous_command_error "${command_name}"
    return 1
  fi

  if [[ -f "${command_name}" ]]; then
    local direct_target=""
    direct_target="$(resolve_script_target "${command_name}")" || true
    if [[ -n "${direct_target}" ]]; then
      local target_type="${direct_target%%$'\t'*}"
      local target_path="${direct_target#*$'\t'}"
      exec_resolved_script_target "${target_type}" "${target_path}" "$@"
      return 0
    fi
  fi

  echo "Command not found: ${command_name}"
  echo "Available commands:"
  list_script

  return 1
}
