#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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
    _* | */_*) return 0 ;;
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
      find -L "${dir}" -maxdepth 2 -type f -name "*.sh" -printf '%P\n' 2>/dev/null
      # Python: list entrypoints only, not import-only modules.
      find -L "${dir}" -maxdepth 2 -type f -name "*.py" -printf '%p\t%P\n' 2>/dev/null |
        while IFS=$'\t' read -r abs_path py_rel; do
          if [[ -x "${abs_path}" ]] || grep -qs '__name__ == .__main__.' "${abs_path}"; then
            printf '%s\n' "${py_rel}"
          fi
        done
    done | sort -u
  )
}

# A script that declares hypr_help_guard is announcing itself as user-facing;
# the line after its "Usage:" is its summary. Scripts without one are pipeline
# hooks other scripts invoke. One awk pass over every candidate, not one grep
# per file.
list_script_described() {
  collect_script_dirs

  local dir=""
  {
    for dir in "${SCRIPT_DIRS[@]}"; do
      find -L "${dir}" -maxdepth 2 -type f -name "*.sh" -printf '%P\t%p\n' 2>/dev/null
      find -L "${dir}" -maxdepth 2 -type f -name "*.py" -printf '%P\t%p\n' 2>/dev/null |
        while IFS=$'\t' read -r py_rel abs_path; do
          if [[ -x "${abs_path}" ]] || grep -qs '__name__ == .__main__.' "${abs_path}"; then
            printf '%s\t%s\n' "${py_rel}" "${abs_path}"
          fi
        done
    done | sort -u
  } | {
    local -a rels=() abses=()
    local rel="" abs=""
    while IFS=$'\t' read -r rel abs; do
      is_internal_script "${rel}" && continue
      rels+=("${rel%.*}")
      abses+=("${abs}")
    done
    [[ ${#abses[@]} -gt 0 ]] || return 0

    awk '
      FNR == 1 { seen[FILENAME] = 1 }
      # A "Usage:" inside a help/usage function is a declared contract; the same
      # string in an error message is not, so only the former is trusted.
      /^[a-zA-Z_]*(usage|help)[a-zA-Z_]*\(\) *\{/ { inhelp = 1 }
      inhelp && /^\}/ { inhelp = 0 }
      /description="/ && /ArgumentParser|^ *description="/ && !(FILENAME in desc) {
        line = $0
        sub(/^.*description="/, "", line)
        sub(/".*$/, "", line)
        if (line != "") desc[FILENAME] = line
        next
      }
      (/hypr_help_guard "Usage:/ || (inhelp && /Usage:/)) && !(FILENAME in desc) {
        text = ""
        # the summary runs until the closing quote of the usage string
        while ((getline line) > 0) {
          # only a prose summary counts: an options table or another heading is not one
          if (line ~ /^[ \t]*-/ && line ~ /[ \t][ \t]/) break
          if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*(cat|printf|echo|EOF|HELP|EOT)/) break
          if (line ~ /^[ \t]*(Options|Usage|Commands|Arguments|Examples|Flags)[: ]/) break
          done = (line ~ /" *"\$@"/)
          sub(/" *"\$@".*$/, "", line)
          gsub(/^[ \t]+|[ \t]+$/, "", line)
          text = (text == "" ? line : text " " line)
          if (done) break
        }
        if (text != "") desc[FILENAME] = text
      }
      END { for (f in seen) printf "%s\t%s\n", f, (f in desc ? desc[f] : "") }
    ' "${abses[@]}" | sort >"${TMPDIR:-/tmp}/.hyprshell-desc.$$"

    local -A summary=()
    while IFS=$'\t' read -r abs rel; do
      summary["${abs}"]="${rel}"
    done <"${TMPDIR:-/tmp}/.hyprshell-desc.$$"
    rm -f "${TMPDIR:-/tmp}/.hyprshell-desc.$$"

    local i=0 text=""
    local -a hooks=()
    printf 'Commands:\n'
    for ((i = 0; i < ${#rels[@]}; i++)); do
      text="${summary["${abses[i]}"]:-}"
      if [[ -n "${text}" ]]; then
        printf '  %-34s %s\n' "${rels[i]}" "${text}"
      else
        hooks+=("${rels[i]}")
      fi
    done
    [[ ${#hooks[@]} -gt 0 ]] || return 0
    printf '\nNo --help text (mostly pipeline hooks; run with care):\n'
    printf '  %s\n' "${hooks[@]}"
  }
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
      hyprshell_load_python_helpers || return 1
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

resolve_command_target() {
  local command_name="${1:-}"
  local target_path=""
  local dir=""

  if [[ -z "${command_name}" ]]; then
    printf 'Usage: hyprshell resolve <command>\n' >&2
    return 1
  fi

  resolve_command_candidates "${command_name}"

  if ((${#CANDIDATES[@]} > 1)); then
    print_ambiguous_command_error "${command_name}"
    return 1
  fi

  if ((${#CANDIDATES[@]} == 0)); then
    printf 'Command not found: %s\n' "${command_name}" >&2
    return 1
  fi

  target_path="${CANDIDATES[0]#*$'\t'}"
  for dir in "${SCRIPT_DIRS[@]}"; do
    if [[ "${target_path}" == "${dir}/"* ]]; then
      printf '%s\n' "${target_path#${dir}/}"
      return 0
    fi
  done

  printf '%s\n' "${target_path}"
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
