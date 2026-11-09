import datetime as dt
import json
import sys

from khal.exceptions import DateTimeParseError
from khal.parse_datetime import eventinfofstr
from khal.settings import get_config

ONE_DAY = dt.timedelta(days=1)
SYNTAX_HINT = "Start with a date or time: tomorrow 14:00 1h Lunch"
TITLE_HINT = "Add a title after the date and time"

config = get_config()
locale = config["locale"]
defaults = config["default"]


def on_selected_day(day, text):
    try:
        dt.datetime.strptime(text.split(" ", 1)[0], locale["timeformat"])
    except ValueError:
        return text
    return dt.date.fromisoformat(day).strftime(locale["dateformat"]) + " " + text


def local(moment, zone):
    return zone.localize(moment).astimezone(locale["local_timezone"])


def with_last_day(event, first, last):
    event["day"] = first.isoformat()
    if last != first:
        event["endDay"] = last.isoformat()
    return event


def parsed(day, text):
    try:
        info = eventinfofstr(on_selected_day(day, text), locale, defaults["default_event_duration"],
                             defaults["default_dayevent_duration"], adjust_reasonably=True)
    except (ValueError, DateTimeParseError):
        return {"error": SYNTAX_HINT}
    if not info["summary"]:
        return {"error": TITLE_HINT}
    event = {"title": info["summary"], "description": info["description"] or "", "allDay": info["allday"]}
    if info["allday"]:
        return with_last_day(event, info["dtstart"], info["dtend"] - ONE_DAY)
    start, end = local(info["dtstart"], info["timezone"]), local(info["dtend"], info["timezone"])
    event["start"] = start.strftime(locale["timeformat"])
    event["end"] = end.strftime(locale["timeformat"])
    return with_last_day(event, start.date(), end.date())


for line in sys.stdin:
    request = line.rstrip("\n")
    day, _, text = request.partition("\t")
    print(json.dumps({"request": request} | parsed(day, text)), flush=True)
