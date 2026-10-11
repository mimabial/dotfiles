read_khal_calendar_table() {
  python3 "${calendar_library}/calendar_catalog.py" 2>/dev/null || printf '{"default":"","calendars":{},"locations":[]}\n'
}

cached_khal_calendar_table() {
  [[ -n "${calendar_table_cache}" ]] || calendar_table_cache="$(read_khal_calendar_table)"
  printf '%s' "${calendar_table_cache}"
}

find_event_files_by_uid() {
  [[ -n "${1:-}" ]] || return 0
  local -a roots=()
  mapfile -t roots < <(cached_khal_calendar_table | jq -r '.calendars[].path | select(. != "")')
  [[ "${#roots[@]}" -gt 0 ]] || roots=("${CALENDAR_VDIR:-$HOME/.calendars}")
  grep -rlF --include='*.ics' "UID:$1" "${roots[@]}" 2>/dev/null
}

read_calendar_title_filters() {
  if [[ -r "${calendar_title_filters_file}" ]] && jq -e 'type == "object"' "${calendar_title_filters_file}" >/dev/null 2>&1; then
    jq -c . "${calendar_title_filters_file}"
  else
    printf '{}\n'
  fi
}

filter_events_by_calendar_title() {
  jq -c --argjson filters "$(read_calendar_title_filters)" '
    map(select(
      ($filters[(.calendar // "")] // "") as $re
      | $re == "" or (try ((.title // "") | test($re)) catch true)
    ))'
}

# khal prints one JSON array per day in the range, so the lines get merged.
read_filtered_khal_events() {
  local start="$1" span="$2"
  khal list \
    --json start-date --json start-time --json end-time \
    --json title --json location --json all-day --json description --json uid \
    --json calendar \
    "${start}" "${span}" 2>/dev/null | jq -s 'add // []' | filter_events_by_calendar_title
}

readonly_calendar_for_directory() {
  cached_khal_calendar_table | jq -r --arg dir "$1" '
    .calendars | to_entries
    | map(select(.value.readonly and ((.value.path | sub("/+$"; "")) == $dir)))
    | (.[0].key // "")'
}

exit_with_readonly_calendar_error() {
  jq -n --arg day "${day}" --arg name "$1" \
    '{day: $day, events: [], error: ($name + " is read-only")}'
  exit 1
}
