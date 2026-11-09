prune_archive_locked() {
  local cutoff="" keep_days="" max_items="" before="" after="" oldest="" tmp=""
  local ms_per_day=86400000

  archive_setting_into keep_days NOTIFY_KEEP_DAYS "${ARCHIVE_DEFAULT_KEEP_DAYS}"
  archive_setting_into max_items NOTIFY_MAX_ITEMS "${ARCHIVE_DEFAULT_MAX_ITEMS}"
  [[ "${keep_days}" =~ ^[0-9]+$ ]] || keep_days="${ARCHIVE_DEFAULT_KEEP_DAYS}"
  [[ "${max_items}" =~ ^[0-9]+$ ]] && ((max_items > 0)) || max_items="${ARCHIVE_DEFAULT_MAX_ITEMS}"
  archive_timestamp_ms_into cutoff
  cutoff=$((cutoff - keep_days * ms_per_day))

  before="$(wc -l <"${ARCHIVE_FILE}" 2>/dev/null || echo 0)"
  if ((before <= max_items)); then
    oldest="$(jq -Rnr 'first(inputs | fromjson? | .ts) // 0' <"${ARCHIVE_FILE}")"
    [[ "${oldest}" =~ ^[0-9]+$ ]] && ((oldest >= cutoff)) && return 0
  fi
  tmp="${ARCHIVE_FILE}.tmp"
  jq -Rnr --argjson cutoff "${cutoff}" --argjson max "${max_items}" \
    '[inputs | fromjson? | select(.ts >= $cutoff)] | .[-$max:] | .[] | tojson' \
    <"${ARCHIVE_FILE}" >"${tmp}" && mv -- "${tmp}" "${ARCHIVE_FILE}" || {
    rm -f -- "${tmp}"
    return 1
  }
  chmod 600 "${ARCHIVE_FILE}" 2>/dev/null || true

  after="$(wc -l <"${ARCHIVE_FILE}" 2>/dev/null || echo 0)"
  ((after < before)) && remove_unreferenced_archive_images
  return 0
}

remove_unreferenced_archive_images() {
  local file=""
  local -A kept=()
  while IFS= read -r file; do
    kept["${file}"]=1
  done < <(jq -Rnr 'inputs | fromjson? | .icon, .preview | select(type == "string" and . != "")' <"${ARCHIVE_FILE}")
  for file in "${ARCHIVE_IMAGES_DIR}"/*; do
    [[ -f "${file}" ]] || continue
    [[ -v 'kept[$file]' ]] || rm -f -- "${file}"
  done
}

remove_archive_entry_locked() {
  local tmp="${ARCHIVE_FILE}.tmp"
  jq -Rnr --arg key "$1" \
    'inputs | fromjson? | select(.key != $key) | tojson' \
    <"${ARCHIVE_FILE}" >"${tmp}" && mv -- "${tmp}" "${ARCHIVE_FILE}" || {
    rm -f -- "${tmp}"
    return 1
  }
  chmod 600 "${ARCHIVE_FILE}" 2>/dev/null || true
  remove_unreferenced_archive_images
}

clear_archive_locked() {
  : >"${ARCHIVE_FILE}"
  chmod 600 "${ARCHIVE_FILE}" 2>/dev/null || true
  rm -f -- "${ARCHIVE_IMAGES_DIR:?}"/* 2>/dev/null || true
}
