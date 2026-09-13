#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell calendar/agenda --day YYYY-MM-DD
       hyprshell calendar/agenda --month YYYY-MM

  --day    Events for one day:   {"day":…,"events":[{start,end,title,location,allDay}]}
  --week   Seven days from START, each with its full event list:
             {"week":START,"days":{"YYYY-MM-DD":[{start,end,title,…}]}}
  --month  Per day, which calendars have something on it, split by whether it
           is an all-day event or a timed one — a holiday marks the day, an
           appointment sits in it:
             {"month":…,"days":{"YYYY-MM-DD":{"allDay":[cal],"timed":[cal]}}}
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
                    removed directly. A read-only calendar is refused.
  --todos           Open todos as JSON: {"todos":[{id,summary,due,…}]}
  --todos-all       The same, including completed ones
  --todo-add        Create a todo, then print the list again:
                      --todo-add --title TEXT [--day YYYY-MM-DD] [--time HH:MM]
                      [--category TAG]... [--priority high|medium|low|none]
                      [--calendar LIST]
  --todo-done ID    Complete the todo with that todoman id
  --todo-open ID    Reopen a completed todo. todoman has no undo, so the
                    VTODO is edited directly: the id is resolved to a file
                    through todoman's own cache, then COMPLETED,
                    PERCENT-COMPLETE and STATUS are undone.
  --todo-edit ID    Update --title and/or --priority on an existing todo
  --todo-delete ID  Remove it
  --calendars       Emit the calendar table khal resolves its config to,
                    plus the LOCATION values already used in writable calendars:
                    {"default":NAME,"calendars":{NAME:{path,color,readonly}},
                     "locations":[TEXT]}

Reads whatever khal is configured to read (~/.calendars by default). Point
vdirsyncer at the same vdir to have CalDAV accounts show up here.

Events are filtered through $XDG_CONFIG_HOME/khal/filters.json when it exists:
{"<calendar>": "<regex>"} keeps only the events of that calendar whose title
matches. A subscribed feed can be a dozen events a day, which would otherwise
be the whole agenda.
USAGE
}

day=""
month=""
week=""
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
calendars_mode=0
priority=""
due_time=""
declare -a categories=()
todos_mode=0
todos_all=0
todo_add=0
todo_done=""
todo_delete=""
todo_open=""
todo_edit=""
table=""
filters="${KHAL_FILTERS:-${XDG_CONFIG_HOME:-$HOME/.config}/khal/filters.json}"
carry_state="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/task-carries.json"

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
    --week)
      week="${2:-}"
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
    --calendars)
      calendars_mode=1
      shift
      ;;
    --priority)
      priority="${2:-}"
      shift 2 || true
      ;;
    --time)
      due_time="${2:-}"
      shift 2 || true
      ;;
    --category)
      [[ -z "${2:-}" ]] || categories+=("${2}")
      shift 2 || true
      ;;
    --todos)
      todos_mode=1
      shift
      ;;
    --todos-all)
      todos_mode=1
      todos_all=1
      shift
      ;;
    --todo-add)
      todo_add=1
      shift
      ;;
    --todo-done)
      todo_done="${2:-}"
      shift 2 || true
      ;;
    --todo-delete)
      todo_delete="${2:-}"
      shift 2 || true
      ;;
    --todo-open)
      todo_open="${2:-}"
      shift 2 || true
      ;;
    --todo-edit)
      todo_edit="${2:-}"
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

khal_calendars() {
  python3 - <<'PY' 2>/dev/null || printf '{"default":"","calendars":{},"locations":[]}\n'
import json
import os

from khal.settings import get_config

MAX_FILES = 5000
MAX_LOCATIONS = 50
UNESCAPE = ((r"\n", " "), (r"\N", " "), (r"\,", ","), (r"\;", ";"), (r"\\", "\\"))


def locations(paths):
    """LOCATION values already used, most frequent first."""
    seen = {}
    budget = MAX_FILES
    for path in paths:
        try:
            names = sorted(os.listdir(path))
        except OSError:
            continue
        for name in names:
            if budget <= 0:
                break
            if not name.endswith(".ics"):
                continue
            budget -= 1
            try:
                with open(os.path.join(path, name), encoding="utf-8", errors="replace") as handle:
                    for line in handle:
                        if not line.startswith("LOCATION"):
                            continue
                        value = line.rstrip("\r\n").split(":", 1)[-1].strip()
                        for old, new in UNESCAPE:
                            value = value.replace(old, new)
                        value = " ".join(value.split())
                        if value:
                            seen[value] = seen.get(value, 0) + 1
            except OSError:
                continue
    ranked = sorted(seen.items(), key=lambda pair: (-pair[1], pair[0].lower()))
    return [value for value, _ in ranked[:MAX_LOCATIONS]]


config = get_config()
calendars = {
    name: {
        "path": values.get("path") or "",
        "color": values.get("color") or "",
        "readonly": bool(values.get("readonly")),
    }
    for name, values in config["calendars"].items()
}
print(json.dumps({
    "default": config["default"].get("default_calendar") or "",
    "calendars": calendars,
    "locations": locations(
        values["path"] for values in calendars.values()
        if values["path"] and not values["readonly"]
    ),
}))
PY
}

khal_table() {
  [[ -n "${table}" ]] || table="$(khal_calendars)"
  printf '%s' "${table}"
}

find_ics() {
  [[ -n "${1:-}" ]] || return 0
  local -a roots=()
  mapfile -t roots < <(khal_table | jq -r '.calendars[].path | select(. != "")')
  [[ "${#roots[@]}" -gt 0 ]] || roots=("${CALENDAR_VDIR:-$HOME/.calendars}")
  grep -rlF --include='*.ics' "UID:$1" "${roots[@]}" 2>/dev/null
}

read_filters() {
  if [[ -r "${filters}" ]] && jq -e 'type == "object"' "${filters}" >/dev/null 2>&1; then
    jq -c . "${filters}"
  else
    printf '{}\n'
  fi
}

apply_filters() {
  jq -c --argjson filters "$(read_filters)" '
    map(select(
      ($filters[(.calendar // "")] // "") as $re
      | $re == "" or (try ((.title // "") | test($re)) catch true)
    ))'
}

todo_cli() {
  command -v todo >/dev/null 2>&1
}

emit_todos() {
  local -a args=(--porcelain list)
  [[ "${todos_all}" -eq 0 ]] || args+=(--status ANY)
  mkdir -p "${carry_state%/*}"
  (
    flock -x 9
    python3 - "${XDG_CACHE_HOME:-$HOME/.cache}/todoman/cache.sqlite3" \
      "${carry_state}" "$((1 - todos_all))" 3< <(todo "${args[@]}" 2>/dev/null) <<'TODOPY'
import datetime, json, os, sqlite3, sys, tempfile

cache, state_path, mutate = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
try:
    todos = json.load(os.fdopen(3))
except (OSError, ValueError):
    print('{"todos":[]}')
    raise SystemExit

uids = {}
try:
    with sqlite3.connect(f"file:{cache}?mode=ro", uri=True) as con:
        uids = dict(con.execute("SELECT id, uid FROM todos"))
except sqlite3.Error:
    pass
for item in todos:
    item["uid"] = str(uids.get(item.get("id"), "id:" + str(item.get("id", ""))))

try:
    with open(state_path, encoding="utf-8") as handle:
        state = json.load(handle)
except (OSError, ValueError):
    state = {}
today = datetime.date.today().isoformat()
old_items = state.get("items", {}) if isinstance(state.get("items"), dict) else {}
notice = 0

if mutate:
    rolled = bool(state.get("day")) and state["day"] < today
    next_items = {}
    for item in todos:
        if item.get("completed") or item.get("due") is not None:
            continue
        uid = item["uid"]
        saved = old_items.get(uid, {})
        carries = max(0, int(saved.get("carries", 0) or 0))
        if rolled and saved:
            carries += 1
            notice += 1
        next_items[uid] = {"firstSeen": saved.get("firstSeen", today), "carries": carries}
    next_state = {"day": today, "items": next_items}
    if next_state != state:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(state_path))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(next_state, handle, separators=(",", ":"))
                handle.write("\n")
            os.replace(tmp, state_path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    state = next_state

items = state.get("items", {})
for item in todos:
    item["carries"] = int(items.get(item["uid"], {}).get("carries", 0) or 0)
todos.sort(key=lambda item: (
    bool(item.get("completed")), item.get("due") if item.get("due") is not None else 99999999999,
    item.get("priority") or 10, str(item.get("summary", "")).lower()))
print(json.dumps({"todos": todos, "carryNotice": notice}, separators=(",", ":")))
TODOPY
  ) 9>"${carry_state}.lock" || printf '{"todos":[]}\n'
}

# The cache is todoman's own id->file map; it is read, never written.
todo_file() {
  python3 - "$1" <<'TODOPY' 2>/dev/null
import os, sqlite3, sys

cache = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "todoman", "cache.sqlite3")
try:
    con = sqlite3.connect(f"file:{cache}?mode=ro", uri=True)
    row = con.execute(
        "SELECT file_path, uid FROM todos WHERE id = ?", (sys.argv[1],)).fetchone()
except sqlite3.Error:
    raise SystemExit(1)
if not row or not row[0]:
    raise SystemExit(1)
path, uid = row
# a cached path can be stale, so it only counts if the file still holds the
# uid the cache expects
try:
    with open(path, encoding="utf-8", errors="replace") as handle:
        if f"UID:{uid}" not in handle.read():
            raise SystemExit(1)
except OSError:
    raise SystemExit(1)
print(path)
TODOPY
}

reopen_todo() {
  local file tmp
  file="$(todo_file "$1")" || return 1
  [[ -n "${file}" ]] || return 1
  tmp="$(mktemp)" || return 1
  awk '
    { sub(/\r$/, "") }
    /^COMPLETED[;:]/ { next }
    /^PERCENT-COMPLETE[;:]/ { next }
    /^STATUS[;:]/ { print "STATUS:NEEDS-ACTION"; next }
    { print }
  ' "${file}" >"${tmp}" || { rm -f "${tmp}"; return 1; }
  mv -- "${tmp}" "${file}" || { rm -f "${tmp}"; return 1; }
}

edit_todo() {
  local file
  file="$(todo_file "$1")" || return 1
  python3 - "${file}" "${title}" "${priority}" <<'TODOPY'
import datetime, os, sys, tempfile
from icalendar import Calendar
from icalendar.prop import vDDDTypes

path, summary, priority = sys.argv[1:]
with open(path, "rb") as handle:
    calendar = Calendar.from_ical(handle.read())
task = calendar.walk("VTODO")[0]
if summary:
    task["SUMMARY"] = summary
if priority:
    task["PRIORITY"] = {"none": 0, "low": 9, "medium": 5, "high": 1}[priority]
now = vDDDTypes(datetime.datetime.now(datetime.timezone.utc))
task["DTSTAMP"], task["LAST-MODIFIED"] = now, now
task["SEQUENCE"] = int(task.get("SEQUENCE", 0)) + 1
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "wb") as handle:
        handle.write(calendar.to_ical())
    os.chmod(tmp, os.stat(path).st_mode)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
TODOPY
}

if [[ "${todos_mode}" -eq 1 ]] || [[ "${todo_add}" -eq 1 ]] ||
  [[ -n "${todo_done}" ]] || [[ -n "${todo_delete}" ]] || [[ -n "${todo_open}" ]] ||
  [[ -n "${todo_edit}" ]]; then
  if ! todo_cli; then
    printf '{"todos":[],"unavailable":true}\n'
    exit 0
  fi
  if [[ -n "${todo_delete}" ]]; then
    todo delete --yes "${todo_delete}" >/dev/null 2>&1 ||
      { jq -n --arg id "${todo_delete}" '{todos: [], error: ("could not delete " + $id)}'; exit 1; }
  fi
  if [[ -n "${todo_open}" ]]; then
    reopen_todo "${todo_open}" ||
      { jq -n --arg id "${todo_open}" '{todos: [], error: ("could not reopen " + $id)}'; exit 1; }
  fi
  if [[ -n "${todo_done}" ]]; then
    todo "done" "${todo_done}" >/dev/null 2>&1 ||
      { jq -n --arg id "${todo_done}" '{todos: [], error: ("could not complete " + $id)}'; exit 1; }
  fi
  if [[ -n "${todo_edit}" ]]; then
    [[ -z "${priority}" || "${priority}" =~ ^(none|low|medium|high)$ ]] ||
      { printf '{"todos":[],"error":"invalid priority"}\n'; exit 1; }
    [[ -n "${title}" || -n "${priority}" ]] ||
      { printf '{"todos":[],"error":"an edit needs a title or priority"}\n'; exit 1; }
    edit_todo "${todo_edit}" ||
      { jq -n --arg id "${todo_edit}" '{todos: [], error: ("could not edit " + $id)}'; exit 1; }
  fi
  if [[ "${todo_add}" -eq 1 ]]; then
    [[ -n "${title}" ]] || { usage >&2; exit 1; }
    declare -a new_todo=(new)
    [[ -z "${calendar}" ]] || new_todo+=(--list "${calendar}")
    if [[ -n "${day}" ]]; then
      if [[ -n "${due_time}" ]]; then
        new_todo+=(--due "${day} ${due_time}")
      else
        new_todo+=(--due "${day}")
      fi
    fi
    [[ -z "${priority}" ]] || new_todo+=(--priority "${priority}")
    for tag in "${categories[@]+"${categories[@]}"}"; do
      new_todo+=(-c "${tag}")
    done
    new_todo+=("${title}")
    todo "${new_todo[@]}" >/dev/null 2>&1 ||
      { printf '{"todos":[],"error":"could not create the todo"}\n'; exit 1; }
  fi
  emit_todos
  exit 0
fi

if [[ "${calendars_mode}" -eq 1 ]] || [[ -n "${show_uid}" ]] ||
  [[ -n "${delete_uid}" ]] || [[ "${add}" -eq 1 ]]; then
  table="$(khal_calendars)"
fi

if [[ "${calendars_mode}" -eq 1 ]]; then
  khal_table
  exit 0
fi

# khal exposes neither recurrence nor alarms, so the file is read directly
if [[ -n "${show_uid}" ]]; then
  file="$(find_ics "${show_uid}" | head -1 || true)"
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

# khal prints one JSON array per day in the range, so the lines get merged.
khal_range() {
  local start="$1" span="$2"
  khal list \
    --json start-date --json start-time --json end-time \
    --json title --json location --json all-day --json description --json uid \
    --json calendar \
    "${start}" "${span}" 2>/dev/null | jq -s 'add // []' | apply_filters
}

readonly_owner() {
  khal_table | jq -r --arg dir "$1" '
    .calendars | to_entries
    | map(select(.value.readonly and ((.value.path | sub("/+$"; "")) == $dir)))
    | (.[0].key // "")'
}

refuse_readonly() {
  jq -n --arg day "${day}" --arg name "$1" \
    '{day: $day, events: [], error: ($name + " is read-only")}'
  exit 1
}

if [[ -n "${delete_uid}" ]]; then
  # a vdir holds one .ics per event, so the UID line identifies the file
  removed=0
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    owner="$(readonly_owner "${file%/*}")"
    [[ -z "${owner}" ]] || refuse_readonly "${owner}"
    rm -f -- "${file}" && removed=1
  done < <(find_ics "${delete_uid}")
  if [[ "${removed}" -eq 0 ]]; then
    printf '{"day":"%s","events":[],"error":"event not found"}\n' "${day}"
    exit 1
  fi
fi

if [[ "${add}" -eq 1 ]]; then
  # khal takes the summary as the trailing words, so it goes last and unquoted
  # pieces before it must all parse as dates, times or a timezone.
  if [[ -n "${calendar}" ]]; then
    [[ "$(khal_table | jq -r --arg name "${calendar}" '.calendars[$name].readonly // false')" == "false" ]] ||
      refuse_readonly "${calendar}"
  else
    calendar="$(khal_table | jq -r '
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
  khal_range "${week}" "7d" | jq --arg week "${week}" "${KHAL_EVENT_JQ}"'{
    week: $week,
    days: (
      map({date: ."start-date", event: khal_event})
      | group_by(.date)
      | map({key: .[0].date, value: map(.event)})
      | from_entries
    )
  }'
elif [[ -n "${day}" ]]; then
  khal_range "${day}" "1d" | jq --arg day "${day}" "${KHAL_EVENT_JQ}"'{
    day: $day,
    events: map(khal_event)
  }'
else
  last_day="$(date -d "${month}-01 +1 month -1 day" +%d 2>/dev/null)" || {
    usage >&2
    exit 1
  }
  khal_range "${month}-01" "${last_day}d" | jq --arg month "${month}" '{
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
