import json
import os

from khal.settings import get_config

MAX_EVENT_FILES = 5000
MAX_USED_LOCATIONS = 50
ICAL_TEXT_ESCAPES = ((r"\n", " "), (r"\N", " "), (r"\,", ","), (r"\;", ";"), (r"\\", "\\"))


def used_locations_by_frequency(paths):
    seen = {}
    budget = MAX_EVENT_FILES
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
                        for old, new in ICAL_TEXT_ESCAPES:
                            value = value.replace(old, new)
                        value = " ".join(value.split())
                        if value:
                            seen[value] = seen.get(value, 0) + 1
            except OSError:
                continue
    ranked = sorted(seen.items(), key=lambda pair: (-pair[1], pair[0].lower()))
    return [value for value, _ in ranked[:MAX_USED_LOCATIONS]]


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
    "locations": used_locations_by_frequency(
        values["path"] for values in calendars.values()
        if values["path"] and not values["readonly"]
    ),
}))
