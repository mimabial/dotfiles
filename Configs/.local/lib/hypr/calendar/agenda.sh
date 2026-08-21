#!/usr/bin/env bash
#
# agenda.sh — Emit calendar events as JSON for the shell's clock panel.
#
# Usage: agenda.sh --day YYYY-MM-DD | --month YYYY-MM
# Depends on: khal, jq
#
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell calendar/agenda --day YYYY-MM-DD
       hyprshell calendar/agenda --month YYYY-MM

  --day    Events for one day:   {"day":…,"events":[{start,end,title,location,allDay}]}
  --month  Event count per day:  {"month":…,"days":{"YYYY-MM-DD":n}}
  --add    Create an event on --day, then print that day's events:
             --add --day YYYY-MM-DD --title TEXT
                   [--start HH:MM] [--end HH:MM] [--end-day YYYY-MM-DD]
                   [--location TEXT] [--description TEXT]
           Omitting --start creates an all-day event; --end-day makes it span
           several days.
  --location TEXT   Where the event is
  --alarm DELTA     Alarm offset khal understands: 0m, 10m, 1h, 1d
  --repeat FREQ     daily, weekly, monthly or yearly
  --calendar NAME   Which calendar to write to (default: khal's first)
  --show UID        Emit one event's full fields, read from its .ics so that
                    RRULE and VALARM survive an edit round trip.
  --delete UID      Remove the event with that UID, then print the day again.
                    khal has no non-interactive delete, so the vdir file is
                    removed directly.

Reads whatever khal is configured to read (~/.calendars by default). Point
vdirsyncer at the same vdir to have CalDAV accounts show up here.
USAGE
}

day=""
month=""
add=0
delete_uid=""
show_uid=""
title=""
start=""
end=""
location=""
description=""
end_day=""
alarm=""
repeat=""
calendar=""

while [ $# -gt 0 ]; do
  case "$1" in
    --day)
      day="${2:-}"
      shift 2 || true
      ;;
    --month)
      month="${2:-}"
      shift 2 || true
      ;;
    --add)
      add=1
      shift
      ;;
    --delete)
      delete_uid="${2:-}"
      shift 2 || true
      ;;
    --show)
      show_uid="${2:-}"
      shift 2 || true
      ;;
    --title)
      title="${2:-}"
      shift 2 || true
      ;;
    --start)
      start="${2:-}"
      shift 2 || true
      ;;
    --end)
      end="${2:-}"
      shift 2 || true
      ;;
    --location)
      location="${2:-}"
      shift 2 || true
      ;;
    --end-day)
      end_day="${2:-}"
      shift 2 || true
      ;;
    --description)
      description="${2:-}"
      shift 2 || true
      ;;
    --alarm)
      alarm="${2:-}"
      shift 2 || true
      ;;
    --repeat)
      repeat="${2:-}"
      shift 2 || true
      ;;
    --calendar)
      calendar="${2:-}"
      shift 2 || true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

# khal exposes neither recurrence nor alarms, so the file is read directly
if [[ -n "${show_uid}" ]]; then
  file="$(grep -rlF --include='*.ics' "UID:${show_uid}" "${CALENDAR_VDIR:-$HOME/.calendars}" 2>/dev/null | head -1)"
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

if [[ -z "${day}" && -z "${month}" ]] || [[ -n "${day}" && -n "${month}" ]]; then
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
  else
    printf '{"month":"%s","days":{},"unavailable":true}\n' "${month}"
  fi
  exit 0
fi

# khal prints one JSON array per day in the range, so the lines get merged.
khal_range() {
  local start="$1" span="$2"
  khal list \
    --json start-date --json start-time --json end-time \
    --json title --json location --json all-day --json description --json uid \
    "${start}" "${span}" 2>/dev/null | jq -s 'add // []'
}

if [[ -n "${delete_uid}" ]]; then
  # a vdir holds one .ics per event, so the UID line identifies the file
  removed=0
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    rm -f -- "${file}" && removed=1
  done < <(grep -rlF --include='*.ics' "UID:${delete_uid}" "${CALENDAR_VDIR:-$HOME/.calendars}" 2>/dev/null)
  if [[ "${removed}" -eq 0 ]]; then
    printf '{"day":"%s","events":[],"error":"event not found"}\n' "${day}"
    exit 1
  fi
fi

if [[ "${add}" -eq 1 ]]; then
  # khal takes the summary as the trailing words, so it goes last and unquoted
  # pieces before it must all parse as dates, times or a timezone.
  [[ -n "${calendar}" ]] || calendar="$(khal printcalendars 2>/dev/null | head -1)"
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

if [[ -n "${day}" ]]; then
  khal_range "${day}" "1d" | jq --arg day "${day}" '{
    day: $day,
    events: map({
      start: (."start-time" // ""),
      end: (."end-time" // ""),
      title: (.title // ""),
      location: (.location // ""),
      description: (.description // ""),
      uid: (.uid // ""),
      allDay: ((."all-day" // "") == "True")
    })
  }'
else
  last_day="$(date -d "${month}-01 +1 month -1 day" +%d 2>/dev/null)" || {
    usage >&2
    exit 1
  }
  khal_range "${month}-01" "${last_day}d" | jq --arg month "${month}" '{
    month: $month,
    days: (map(."start-date") | group_by(.) | map({key: .[0], value: length}) | from_entries)
  }'
fi
