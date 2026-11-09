ARCHIVE_STORE_DIR="${HYPR_STATE_HOME}/notifications"
ARCHIVE_FILE="${ARCHIVE_STORE_DIR}/archive.jsonl"
ARCHIVE_IMAGES_DIR="${ARCHIVE_STORE_DIR}/images"
ARCHIVE_SEEN_FILE="${ARCHIVE_STORE_DIR}/seen"

ensure_notification_archive() {
  [[ -d "${ARCHIVE_IMAGES_DIR}" && -f "${ARCHIVE_FILE}" && -f "${ARCHIVE_SEEN_FILE}" ]] && return 0
  mkdir -p "${ARCHIVE_IMAGES_DIR}"
  chmod 700 "${ARCHIVE_STORE_DIR}" "${ARCHIVE_IMAGES_DIR}" 2>/dev/null || true
  [[ -e "${ARCHIVE_FILE}" ]] || : >"${ARCHIVE_FILE}"
  [[ -e "${ARCHIVE_SEEN_FILE}" ]] || printf '0\n' >"${ARCHIVE_SEEN_FILE}"
  chmod 600 "${ARCHIVE_FILE}" "${ARCHIVE_SEEN_FILE}" 2>/dev/null || true
}

with_archive_lock() {
  local lock_file=""
  hypr_lock_path_into lock_file notify_archive 2>/dev/null || lock_file="${ARCHIVE_STORE_DIR}/.lock"
  (
    exec {archive_lock_fd}>"${lock_file}"
    flock "${archive_lock_fd}"
    "$@"
  )
}

read_archive_seen_timestamp_into() {
  local -n seen_timestamp_ref="$1"

  seen_timestamp_ref=0
  [[ -r "${ARCHIVE_SEEN_FILE}" ]] && { IFS= read -r seen_timestamp_ref <"${ARCHIVE_SEEN_FILE}" || true; }
  [[ "${seen_timestamp_ref}" =~ ^[0-9]+$ ]] || seen_timestamp_ref=0
}
