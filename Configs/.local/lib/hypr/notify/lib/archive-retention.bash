prune_archive_locked() {
  local cutoff="" keep_days="" max_items="" before="" after="" oldest="" tmp=""
  local ms_per_day=86400000

  keep_days="$(archive_setting NOTIFY_KEEP_DAYS "${ARCHIVE_DEFAULT_KEEP_DAYS}")"
  max_items="$(archive_setting NOTIFY_MAX_ITEMS "${ARCHIVE_DEFAULT_MAX_ITEMS}")"
  [[ "${keep_days}" =~ ^[0-9]+$ ]] || keep_days="${ARCHIVE_DEFAULT_KEEP_DAYS}"
  [[ "${max_items}" =~ ^[0-9]+$ ]] && ((max_items > 0)) || max_items="${ARCHIVE_DEFAULT_MAX_ITEMS}"
  cutoff=$(($(archive_timestamp_ms) - keep_days * ms_per_day))

  before="$(wc -l <"${archive}" 2>/dev/null || echo 0)"
  if ((before <= max_items)); then
    oldest="$(jq -Rnr 'first(inputs | fromjson? | .ts) // 0' <"${archive}")"
    [[ "${oldest}" =~ ^[0-9]+$ ]] && ((oldest >= cutoff)) && return 0
  fi
  tmp="${archive}.tmp"
  jq -Rnr --argjson cutoff "${cutoff}" --argjson max "${max_items}" \
    '[inputs | fromjson? | select(.ts >= $cutoff)] | .[-$max:] | .[] | tojson' \
    <"${archive}" >"${tmp}" && mv -- "${tmp}" "${archive}" || {
    rm -f -- "${tmp}"
    return 1
  }
  chmod 600 "${archive}" 2>/dev/null || true

  after="$(wc -l <"${archive}" 2>/dev/null || echo 0)"
  ((after < before)) && remove_unreferenced_archive_images
  return 0
}

remove_unreferenced_archive_images() {
  local file=""
  local -A kept=()
  while IFS= read -r file; do
    kept["${file}"]=1
  done < <(jq -Rnr 'inputs | fromjson? | .icon, .preview | select(type == "string" and . != "")' <"${archive}")
  for file in "${images}"/*; do
    [[ -f "${file}" ]] || continue
    [[ -v 'kept[$file]' ]] || rm -f -- "${file}"
  done
}

remove_archive_entry_locked() {
  local tmp="${archive}.tmp"
  jq -Rnr --arg key "$1" \
    'inputs | fromjson? | select(.key != $key) | tojson' \
    <"${archive}" >"${tmp}" && mv -- "${tmp}" "${archive}" || {
    rm -f -- "${tmp}"
    return 1
  }
  chmod 600 "${archive}" 2>/dev/null || true
  remove_unreferenced_archive_images
}

clear_archive_locked() {
  : >"${archive}"
  chmod 600 "${archive}" 2>/dev/null || true
  rm -f -- "${images:?}"/* 2>/dev/null || true
}
