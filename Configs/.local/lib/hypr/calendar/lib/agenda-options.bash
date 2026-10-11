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
calendar_table_cache=""
calendar_title_filters_file="${KHAL_FILTERS:-${XDG_CONFIG_HOME:-$HOME/.config}/khal/filters.json}"

parse_agenda_options() {
  while (($#)); do
    case "$1" in
      --add) add=1; shift; continue ;;
      --calendars) calendars_mode=1; shift; continue ;;
      --todos) todos_mode=1; shift; continue ;;
      --todos-all) todos_mode=1; todos_all=1; shift; continue ;;
      --todo-add) todo_add=1; shift; continue ;;
      -h | --help) usage; exit 0 ;;
    esac
    (($# >= 2)) || { usage >&2; return 1; }
    case "$1" in
      --day) day=$2 ;;
      --month) month=$2 ;;
      --week) week=$2 ;;
      --delete) delete_uid=$2 ;;
      --show) show_uid=$2 ;;
      --title) title=$2 ;;
      --start) start=$2 ;;
      --end) end=$2 ;;
      --location) location=$2 ;;
      --end-day) end_day=$2 ;;
      --description) description=$2 ;;
      --alarm) alarm=$2 ;;
      --repeat) repeat=$2 ;;
      --calendar) calendar=$2 ;;
      --priority) priority=$2 ;;
      --time) due_time=$2 ;;
      --category) [[ -z $2 ]] || categories+=("$2") ;;
      --todo-done) todo_done=$2 ;;
      --todo-delete) todo_delete=$2 ;;
      --todo-open) todo_open=$2 ;;
      --todo-edit) todo_edit=$2 ;;
      *) usage >&2; return 1 ;;
    esac
    shift 2
  done
}
