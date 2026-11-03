notification_is_excluded() {
  local app="$1" tag="$2" entry="" skip_list=""
  local -a skip=()

  archive_setting_into skip_list NOTIFY_ARCHIVE_SKIP_APPS 'Claude Code'
  IFS='|' read -ra skip <<<"${skip_list}"
  for entry in "${skip[@]}"; do
    [[ -n "${entry}" && "${app}" == "${entry}" ]] && return 0
  done
  archive_setting_into skip_list NOTIFY_ARCHIVE_SKIP_TAGS 'submap-hint'
  IFS='|' read -ra skip <<<"${skip_list}"
  for entry in "${skip[@]}"; do
    [[ -n "${entry}" && "${tag}" == "${entry}" ]] && return 0
  done
  return 1
}

archive_add() {
  local app="${DUNST_APP_NAME:-}" summary="${DUNST_SUMMARY:-}" body="${DUNST_BODY:-}"
  local urgency="${DUNST_URGENCY:-NORMAL}" category="${DUNST_CATEGORY:-}"
  local desktop="${DUNST_DESKTOP_ENTRY:-}" source_icon="${DUNST_ICON_PATH:-}"
  local id="${DUNST_ID:-0}" tag="${DUNST_STACK_TAG:-}"
  local icon="" preview="" stamp="" key="" sensitive="" entry=""

  [[ -n "${summary}${body}" ]] || return 0
  notification_is_excluded "${app}" "${tag}" && return 0
  ensure_notification_archive

  archive_timestamp_ms_into stamp
  [[ "${id}" =~ ^[0-9]+$ ]] || id=0
  key="${stamp}-${id}"
  sensitive="$(python3 "${HYPR_LIB_DIR}/notify/verification.py" record "${key}")" || return 1
  if [[ "${sensitive}" == true ]]; then
    app="Verification"
    summary="Verification notification"
    body="[redacted]"
    desktop=""
    source_icon=""
    category=""
  fi

  if [[ -n "${source_icon}" && -f "${source_icon}" ]]; then
    if is_theme_owned_icon "${source_icon}"; then
      icon="${source_icon}"
    else
      icon="$(store_notification_image "${source_icon}" || true)"
      preview="${icon}"
    fi
  fi

  entry="$(jq -cn \
    --arg key "${key}" --argjson ts "${stamp}" --arg app "${app}" --arg summary "${summary}" \
    --arg body "${body}" --arg urgency "${urgency}" --arg category "${category}" \
    --arg desktop "${desktop}" --arg icon "${icon}" --arg preview "${preview}" \
    '$ARGS.named')"
  with_archive_lock append_and_prune_archive_locked "${entry}"
}

append_and_prune_archive_locked() {
  printf '%s\n' "$1" >>"${archive}"
  prune_archive_locked || true
}

archive_list() {
  local limit="${1:-${ARCHIVE_DEFAULT_LIMIT}}"
  [[ "${limit}" =~ ^[0-9]+$ ]] || limit="${ARCHIVE_DEFAULT_LIMIT}"
  ensure_notification_archive
  jq -Rcn --argjson limit "${limit}" \
    '[inputs | fromjson?] | reverse | .[:$limit]' <"${archive}" 2>/dev/null \
    || printf '[]\n'
}

archive_remove() {
  local key="$1"
  [[ -n "${key}" ]] || {
    printf '{"ok":false,"error":"missing key"}\n'
    return 1
  }
  ensure_notification_archive
  with_archive_lock remove_archive_entry_locked "${key}" || {
    printf '{"ok":false,"error":"archive rewrite failed"}\n'
    return 1
  }
  printf '{"ok":true,"removed":%s}\n' "$(jq -Rn --arg k "${key}" '$k')"
}

archive_clear() {
  ensure_notification_archive
  with_archive_lock clear_archive_locked
  printf '{"ok":true,"cleared":true}\n'
}

archive_seen() {
  local seen=""
  ensure_notification_archive
  if [[ -n "${1:-}" ]]; then
    [[ "$1" =~ ^[0-9]+$ ]] || {
      printf '{"ok":false,"error":"not a timestamp"}\n'
      return 1
    }
    printf '%s\n' "$1" >"${seen_file}"
    chmod 600 "${seen_file}" 2>/dev/null || true
  fi
  read_archive_seen_timestamp_into seen
  printf '{"ok":true,"seen":%s}\n' "${seen}"
}

archive_unread() {
  local seen=""
  ensure_notification_archive
  read_archive_seen_timestamp_into seen
  printf '{"ok":true,"unread":%s}\n' \
    "$(jq -Rn --argjson seen "${seen}" \
      '[inputs | fromjson? | select(.ts > $seen)] | length' <"${archive}")"
}

archive_snapshot() {
  local limit="${1:-${ARCHIVE_DEFAULT_LIMIT}}" seen=""
  [[ "${limit}" =~ ^[0-9]+$ ]] || limit="${ARCHIVE_DEFAULT_LIMIT}"
  ensure_notification_archive
  read_archive_seen_timestamp_into seen
  jq -Rcn --argjson limit "${limit}" --argjson seen "${seen}" \
    '[inputs | fromjson?] | {seen: $seen, unread: ([.[] | select(.ts > $seen)] | length), entries: (reverse | .[:$limit])}' \
    <"${archive}" 2>/dev/null || printf '{"seen":0,"unread":0,"entries":[]}\n'
}
