import json
from datetime import datetime
from functools import cache
from pathlib import Path


@cache
def weather_icons():
    try:
        return json.loads((Path(__file__).parent.parent / "weather_codes.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"default": "󰖐"}


def weather_icon(weather_code, is_day=None):
    codes = weather_icons()
    icon = codes.get(str(weather_code), codes.get("default", "󰖐"))
    return codes.get("night", {}).get(str(weather_code), icon) if is_day == 0 else icon


def condition_is_day(condition, astronomy):
    if condition.get("is_day") is not None:
        return condition["is_day"]
    stamp = condition.get("localObsDateTime", condition.get("time", ""))
    try:
        clock = (datetime.fromisoformat(stamp) if "T" in stamp
                 else datetime.strptime(stamp, "%Y-%m-%d %I:%M %p")).time()
        sunrise = datetime.strptime(astronomy["sunrise"], "%I:%M %p").time()
        sunset = datetime.strptime(astronomy["sunset"], "%I:%M %p").time()
        return sunrise <= clock < sunset
    except (KeyError, TypeError, ValueError):
        return None


def annotate_day_icons(weather):
    for day in weather.get("weather", []):
        code = day.get("weatherCode")
        hours = day.get("hourly") or []
        if not code:
            midday = hours[len(hours) // 2] if hours else {}
            code = midday.get("weatherCode")
        if code:
            day["icon"] = weather_icon(code)
        astronomy = (day.get("astronomy") or [{}])[0]
        for hour in hours:
            stamp = str(hour.get("time", ""))
            if stamp.isdigit():
                hour["time"] = f"{day.get('date')}T{int(stamp) // 100:02d}:{int(stamp) % 100:02d}"
            if hour.get("weatherCode"):
                hour["icon"] = weather_icon(hour["weatherCode"], condition_is_day(hour, astronomy))
    return weather
