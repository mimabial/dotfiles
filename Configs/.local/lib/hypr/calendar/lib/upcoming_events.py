import datetime as dt
import json

from khal.cli import build_collection
from khal.settings import get_config

LONGEST_ALARM_LEAD = dt.timedelta(weeks=1)
ONE_DAY = dt.timedelta(days=1)

config = get_config()
local_zone = config["locale"]["local_timezone"]


def epoch_seconds(moment):
    if not isinstance(moment, dt.datetime):
        moment = dt.datetime.combine(moment, dt.time())
    if moment.tzinfo is None:
        moment = local_zone.localize(moment)
    return int(moment.timestamp())


def occurrence(event):
    last = event.end_local + ONE_DAY if event.allday else event.end_local
    return {
        "uid": event.uid,
        "title": event.summary,
        "location": event.location,
        "calendar": event.calendar,
        "allDay": event.allday,
        "start": epoch_seconds(event.start_local),
        "end": epoch_seconds(last),
        "alarms": [int(offset.total_seconds()) for offset, _ in event.alarms],
    }


window_start = dt.datetime.combine(dt.date.today(), dt.time())
window_end = window_start + ONE_DAY + LONGEST_ALARM_LEAD
collection = build_collection(config, None)
events = list(collection.get_localized(local_zone.localize(window_start), local_zone.localize(window_end)))
events += collection.get_floating(window_start, window_end)
print(json.dumps({
    "dirs": [values["path"] for values in config["calendars"].values()],
    "events": sorted((occurrence(event) for event in events), key=lambda item: item["start"]),
}))
