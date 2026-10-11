import json
from functools import cache
from pathlib import Path


@cache
def weather_icons():
    try:
        return json.loads((Path(__file__).parent.parent / "weather_codes.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"default": "󰖐"}


def weather_icon(weather_code):
    codes = weather_icons()
    return codes.get(str(weather_code), codes.get("default", "󰖐"))


def annotate_day_icons(weather):
    for day in weather.get("weather", []):
        code = day.get("weatherCode")
        hours = day.get("hourly") or []
        if not code:
            midday = hours[len(hours) // 2] if hours else {}
            code = midday.get("weatherCode")
        if code:
            day["icon"] = weather_icon(code)
        for hour in hours:
            if hour.get("weatherCode"):
                hour["icon"] = weather_icon(hour["weatherCode"])
            stamp = str(hour.get("time", ""))
            if stamp.isdigit():
                hour["time"] = f"{day.get('date')}T{int(stamp) // 100:02d}:{int(stamp) % 100:02d}"
    return weather
