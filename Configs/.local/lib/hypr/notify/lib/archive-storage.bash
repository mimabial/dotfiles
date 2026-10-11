store="${HYPR_STATE_HOME}/notifications"
archive="${store}/archive.jsonl"
images="${store}/images"
seen_file="${store}/seen"

ensure_notification_archive() {
  [[ -d "${images}" && -f "${archive}" && -f "${seen_file}" ]] && return 0
  mkdir -p "${images}"
  chmod 700 "${store}" "${images}" 2>/dev/null || true
  [[ -e "${archive}" ]] || : >"${archive}"
  [[ -e "${seen_file}" ]] || printf '0\n' >"${seen_file}"
  chmod 600 "${archive}" "${seen_file}" 2>/dev/null || true
}

with_archive_lock() {
  local lock_file=""
  lock_file="$(hypr_lock_path_ensure_parent notify_archive 2>/dev/null)" || lock_file="${store}/.lock"
  (
    exec {archive_lock_fd}>"${lock_file}"
    flock "${archive_lock_fd}"
    "$@"
  )
}

read_archive_seen_timestamp() {
  local value=""
  value="$(cat -- "${seen_file}" 2>/dev/null || echo 0)"
  [[ "${value}" =~ ^[0-9]+$ ]] || value=0
  printf '%s' "${value}"
}
