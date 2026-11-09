update_runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
update_cache_path="${update_runtime_dir}/update_status.json"

updates_remove_check_database() {
  local exit_code="${1:-$?}"
  if [[ -n "${update_database_dir}" ]]; then
    rm -rf "${update_database_dir}" 2>/dev/null || true
    update_database_dir=""
  fi
  return "${exit_code}"
}

updates_handle_signal() {
  local signal_exit_code="$1"
  updates_remove_check_database "${signal_exit_code}"
  exit "${signal_exit_code}"
}

updates_normalize_count() {
  [[ "${1:-0}" =~ ^[0-9]+$ ]] && printf '%s\n' "${1:-0}" || printf '0\n'
}

updates_last_upgrade_epoch() {
  local line=""

  line="$(tac /var/log/pacman.log 2>/dev/null | grep -m1 'starting full system upgrade' || true)"
  [[ "${line}" =~ ^\[([^]]+)\] ]] && date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || printf '0\n'
}

updates_capture_query_into() {
  local out_var="$1"
  local -n query_errors_ref="$2"
  local label="$3"
  shift 3

  local output=""
  local stderr_file=""
  local stderr_output=""
  local rc=0

  stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/system-update-${label}.XXXXXX")" || return 1
  output="$("$@" 2>"${stderr_file}")" || rc=$?
  stderr_output="$(<"${stderr_file}")"
  rm -f "${stderr_file}"

  printf -v "${out_var}" '%s' "${output}"

  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi

  if [[ -n "${output}" && -z "${stderr_output}" ]]; then
    return 0
  fi

  case "${rc}" in
    1 | 2)
      [[ -z "${stderr_output}" ]] && return 0
      ;;
  esac

  query_errors_ref+=("${label}: ${stderr_output:-exit ${rc}}")
}

updates_read_cached_counts_into() {
  local -n repo_count_ref="$1" aur_count_ref="$2" flatpak_count_ref="$3"
  IFS=$'\t' read -r repo_count_ref aur_count_ref flatpak_count_ref < <(
    jq -r '[.packages.pacman, .packages.aur, .packages.flatpak] | map(length) | @tsv' "${update_cache_path}"
  )
  repo_count_ref="$(updates_normalize_count "${repo_count_ref}")"
  aur_count_ref="$(updates_normalize_count "${aur_count_ref}")"
  flatpak_count_ref="$(updates_normalize_count "${flatpak_count_ref}")"
}

updates_require_cached_report() {
  [[ -s "${update_cache_path}" ]] && jq -e '.packages | type == "object"' "${update_cache_path}" >/dev/null 2>&1 && return 0
  echo "No upgrade info found. Please run the script without parameters first."
  return 1
}

