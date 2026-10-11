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
  local label="$2"
  shift 2

  local output=""
  local stderr_file=""
  local stderr_output=""
  local rc=0

  stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/system-update-${label}.XXXXXX")" || return 1
  set +e
  output="$("$@" 2>"${stderr_file}")"
  rc=$?
  set -e
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

  system_update_errors+=("${label}: ${stderr_output:-exit ${rc}}")
}

updates_read_cached_counts() {
  IFS=$'\t' read -r repo_update_count aur_update_count flatpak_update_count < <(
    jq -r '[.packages.pacman, .packages.aur, .packages.flatpak] | map(length) | @tsv' "${update_cache_path}"
  )
  repo_update_count="$(updates_normalize_count "${repo_update_count}")"
  aur_update_count="$(updates_normalize_count "${aur_update_count}")"
  flatpak_update_count="$(updates_normalize_count "${flatpak_update_count}")"
}

updates_require_cached_report() {
  [[ -s "${update_cache_path}" ]] && jq -e '.packages | type == "object"' "${update_cache_path}" >/dev/null 2>&1 && return 0
  echo "No upgrade info found. Please run the script without parameters first."
  return 1
}

