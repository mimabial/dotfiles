#!/usr/bin/env bash
set -euo pipefail

calendar_library="${BASH_SOURCE[0]%/*}/lib"
source "${calendar_library}/agenda-options.bash"
parse_agenda_options "$@" || exit 1

source "${calendar_library}/calendar-events.bash"
source "${calendar_library}/todo-actions.bash"

if [[ "${todos_mode}" -eq 1 || "${todo_add}" -eq 1 ]] || [[ -n "${todo_done}${todo_delete}${todo_open}${todo_edit}" ]]; then
  if ! todoman_available; then
    printf '{"todos":[],"unavailable":true}\n'
    exit 0
  fi
  [[ -z "${todo_delete}" ]] || delete_todo "${todo_delete}" || exit_with_todo_error "could not delete ${todo_delete}"
  [[ -z "${todo_open}" ]] || reopen_todo "${todo_open}" || exit_with_todo_error "could not reopen ${todo_open}"
  [[ -z "${todo_done}" ]] || complete_todo "${todo_done}" || exit_with_todo_error "could not complete ${todo_done}"
  if [[ -n "${todo_edit}" ]]; then
    [[ -z "${priority}" || "${priority}" =~ ^(none|low|medium|high)$ ]] || exit_with_todo_error "invalid priority"
    [[ -n "${title}${priority}" ]] || exit_with_todo_error "an edit needs a title or priority"
    edit_todo "${todo_edit}" "${title}" "${priority}" || exit_with_todo_error "could not edit ${todo_edit}"
  fi
  if [[ "${todo_add}" -eq 1 ]]; then
    [[ -n "${title}" ]] || { usage >&2; exit 1; }
    add_todo "${title}" "${calendar}" "${day}" "${due_time}" "${priority}" "${categories[@]+"${categories[@]}"}" ||
      exit_with_todo_error "could not create the todo"
  fi
  emit_todos "${todos_all}"
  exit 0
fi

if [[ "${calendars_mode}" -eq 1 ]] || [[ -n "${show_uid}" ]] ||
  [[ -n "${delete_uid}" ]] || [[ "${add}" -eq 1 ]]; then
  calendar_table_cache="$(read_khal_calendar_table)"
fi

if [[ "${calendars_mode}" -eq 1 ]]; then
  cached_khal_calendar_table
  exit 0
fi

# khal exposes neither recurrence nor alarms, so the file is read directly
if [[ -n "${show_uid}" ]]; then
  file="$(find_event_files_by_uid "${show_uid}" | head -1 || true)"
  if [[ -z "${file}" ]]; then
    printf '{"error":"event not found"}\n'
    exit 1
  fi
  awk '
    { sub(/\r$/, "") }
    /^BEGIN:VEVENT/ { inside = 1 }
    /^END:VEVENT/   { if (line != "") print line; line = ""; inside = 0; next }
    !inside { next }
    /^[ \t]/ { line = line substr($0, 2); next }
    { if (line != "") print line; line = $0 }
  ' "${file}" | jq -R -s '
    def field($name): (. | map(select(startswith($name))) | first // "") ;
    def value($name): (field($name) | sub("^[^:]*:"; "")) ;
    split("\n") | map(select(length > 0)) |
    {
      title: value("SUMMARY"),
      location: value("LOCATION"),
      description: value("DESCRIPTION"),
      allDay: (field("DTSTART") | test("VALUE=DATE:")),
      startRaw: value("DTSTART"),
      endRaw: value("DTEND"),
      repeat: (value("RRULE") | if . == "" then "" else (capture("FREQ=(?<f>[A-Z]+)").f | ascii_downcase) end),
      alarm: (value("TRIGGER") | if . == "" then "" else . end)
    }'
  exit 0
fi

selected=0
[[ -z "${day}" ]] || selected=$((selected + 1))
[[ -z "${month}" ]] || selected=$((selected + 1))
[[ -z "${week}" ]] || selected=$((selected + 1))
if [[ "${selected}" -ne 1 ]]; then
  usage >&2
  exit 1
fi

if [[ "${add}" -eq 1 ]] && { [[ -z "${day}" ]] || [[ -z "${title}" ]]; }; then
  usage >&2
  exit 1
fi

if [[ -n "${delete_uid}" ]] && [[ -z "${day}" ]]; then
  usage >&2
  exit 1
fi

# A missing or unconfigured khal is not an error here: the panel just shows
# nothing rather than an angry empty state.
if ! command -v khal >/dev/null 2>&1; then
  if [[ -n "${day}" ]]; then
    printf '{"day":"%s","events":[],"unavailable":true}\n' "${day}"
  elif [[ -n "${week}" ]]; then
    printf '{"week":"%s","days":{},"unavailable":true}\n' "${week}"
  else
    printf '{"month":"%s","days":{},"unavailable":true}\n' "${month}"
  fi
  exit 0
fi

if [[ -n "${delete_uid}" ]]; then
  # a vdir holds one .ics per event, so the UID line identifies the file
  removed=0
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    owner="$(readonly_calendar_for_directory "${file%/*}")"
    [[ -z "${owner}" ]] || exit_with_readonly_calendar_error "${owner}"
    rm -f -- "${file}" && removed=1
  done < <(find_event_files_by_uid "${delete_uid}")
  if [[ "${removed}" -eq 0 ]]; then
    printf '{"day":"%s","events":[],"error":"event not found"}\n' "${day}"
    exit 1
  fi
fi

if [[ "${add}" -eq 1 ]]; then
  # khal takes the summary as the trailing words, so it goes last and unquoted
  # pieces before it must all parse as dates, times or a timezone.
  if [[ -n "${calendar}" ]]; then
    [[ "$(cached_khal_calendar_table | jq -r --arg name "${calendar}" '.calendars[$name].readonly // false')" == "false" ]] ||
      exit_with_readonly_calendar_error "${calendar}"
  else
    calendar="$(cached_khal_calendar_table | jq -r '
      .calendars as $all
      | (.default // "") as $preferred
      | if $all[$preferred].readonly == false then $preferred
        else ($all | to_entries | map(select(.value.readonly | not)) | (.[0].key // "")) end')"
  fi
  declare -a new_args=(new)
  [[ -n "${calendar}" ]] && new_args+=(-a "${calendar}")
  [[ -n "${location}" ]] && new_args+=(-l "${location}")
  [[ -n "${alarm}" ]] && new_args+=(-m "${alarm}")
  [[ -n "${repeat}" ]] && new_args+=(-r "${repeat}")
  if [[ -n "${start}" ]]; then
    new_args+=("${day} ${start}")
    if [[ -n "${end}" ]]; then
      new_args+=("${end_day:-${day}} ${end}")
    elif [[ -n "${end_day}" ]]; then
      new_args+=("${end_day} ${start}")
    fi
  else
    new_args+=("${day}")
    [[ -n "${end_day}" ]] && new_args+=("${end_day}")
  fi
  new_args+=("${title}")
  [[ -n "${description}" ]] && new_args+=("::" "${description}")
  if ! khal "${new_args[@]}" >/dev/null 2>&1; then
    printf '{"day":"%s","events":[],"error":"could not create the event"}\n' "${day}"
    exit 1
  fi
fi

# khal's own keys are hyphenated and inconsistently present; the day and week
# views must expose exactly the same event shape.
KHAL_EVENT_JQ='def khal_event: {
  start: (."start-time" // ""),
  end: (."end-time" // ""),
  title: (.title // ""),
  location: (.location // ""),
  description: (.description // ""),
  uid: (.uid // ""),
  calendar: (.calendar // ""),
  allDay: ((."all-day" // "") == "True")
};'

if [[ -n "${week}" ]]; then
  read_filtered_khal_events "${week}" "7d" | jq --arg week "${week}" "${KHAL_EVENT_JQ}"'{
    week: $week,
    days: (
      map({date: ."start-date", event: khal_event})
      | group_by(.date)
      | map({key: .[0].date, value: map(.event)})
      | from_entries
    )
  }'
elif [[ -n "${day}" ]]; then
  read_filtered_khal_events "${day}" "1d" | jq --arg day "${day}" "${KHAL_EVENT_JQ}"'{
    day: $day,
    events: map(khal_event)
  }'
else
  last_day="$(date -d "${month}-01 +1 month -1 day" +%d 2>/dev/null)" || {
    usage >&2
    exit 1
  }
  read_filtered_khal_events "${month}-01" "${last_day}d" | jq --arg month "${month}" '{
    month: $month,
    days: (
      map({
        date: ."start-date",
        calendar: (.calendar // ""),
        allDay: ((."all-day" // "") == "True")
      })
      | group_by(.date)
      | map({
        key: .[0].date,
        value: {
          allDay: (map(select(.allDay) | .calendar) | unique),
          timed: (map(select(.allDay | not) | .calendar) | unique)
        }
      })
      | from_entries
    )
  }'
fi
