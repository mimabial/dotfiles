from calendar import monthrange
from datetime import date, datetime, timedelta, timezone
from functools import cache
from math import cos, tau
from zoneinfo import ZoneInfo

from astral import Observer, SunDirection
from astral.julian import julianday, julianday_to_juliancentury
from astral.moon import phase, riseset
from astral.sun import blue_hour, golden_hour, sun_apparent_long

PHASE_CYCLE = 28
SOLSTICE_PRECISION = timedelta(minutes=1)
MOON_PHASES = (
    ("New moon", "New"),
    ("Waxing crescent", "Wax cres."),
    ("First quarter", "1st qtr"),
    ("Waxing gibbous", "Wax gib."),
    ("Full moon", "Full"),
    ("Waning gibbous", "Wan gib."),
    ("Last quarter", "Last qtr"),
    ("Waning crescent", "Wan cres."),
)
MOON_GLYPHS = (
    "\ue3d5\ue3d6\ue3d7\ue3d8\ue3d9\ue3da\ue3db\ue3dc\ue3dd\ue3de\ue3df\ue3e0\ue3e1\ue3e2\ue3e3"
    "\ue3c8\ue3c9\ue3ca\ue3cb\ue3cc\ue3cd\ue3ce\ue3cf\ue3d0\ue3d1\ue3d2\ue3d3\ue3d4"
)
MOON_ILLUMINATIONS = tuple(
    (1 - cos(tau * index / len(MOON_GLYPHS))) * 100 / 2
    for index in range(len(MOON_GLYPHS) // 2 + 1)
)


def event_clock(calculate, observer, day, tzinfo, **kwargs):
    try:
        result = calculate(observer, day, tzinfo=tzinfo, **kwargs)
    except ValueError:
        return "No event"
    if result is None:
        return "No event"
    times = result if isinstance(result, tuple) else (result,)
    return " – ".join(stamp.strftime("%H:%M") for stamp in times)


def moon_clocks(observer, day, tzinfo):
    midnight = datetime.combine(day, datetime.min.time(), tzinfo)
    first = midnight.astimezone(timezone.utc).date()
    last = ((midnight + timedelta(days=1)).astimezone(timezone.utc) - timedelta.resolution).date()
    times = [None, None]
    for offset in range((last - first).days + 1):
        for index, stamp in enumerate(riseset(first + timedelta(days=offset), observer)):
            if stamp is None:
                continue
            local = stamp.astimezone(tzinfo)
            if local.date() == day and times[index] is None:
                times[index] = local
    return tuple(stamp.strftime("%H:%M") if stamp is not None else "No event" for stamp in times)


@cache
def solstice(year, month, longitude):
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    end = start + timedelta(days=monthrange(year, month)[1])
    while end - start > SOLSTICE_PRECISION:
        middle = start + (end - start) / 2
        angle = sun_apparent_long(julianday_to_juliancentury(julianday(middle)))
        if angle < longitude:
            start = middle
        else:
            end = middle
    return start + (end - start) / 2


def next_solstice(day, latitude, tzinfo):
    for year in (day.year, day.year + 1):
        for month, longitude in ((6, 90), (12, 270)):
            stamp = solstice(year, month, longitude).astimezone(tzinfo).date()
            if stamp >= day:
                season = "Summer" if (month == 6) == (latitude >= 0) else "Winter"
                return {"date": stamp.isoformat(), "season": season}


def annotate_astronomy(weather, latitude, longitude, timezone_name):
    observer, tzinfo = Observer(latitude, longitude), ZoneInfo(timezone_name)
    for forecast in weather["weather"]:
        day = date.fromisoformat(forecast["date"])
        cycle = phase(day) / PHASE_CYCLE
        name, short_name = MOON_PHASES[round(cycle * len(MOON_PHASES)) % len(MOON_PHASES)]
        illumination = round((1 - cos(tau * cycle)) * 100 / 2)
        step = min(range(len(MOON_ILLUMINATIONS)), key=lambda index: abs(MOON_ILLUMINATIONS[index] - illumination))
        icon = MOON_GLYPHS[step if cycle < 1 / 2 else -step]
        moonrise_clock, moonset_clock = moon_clocks(observer, day, tzinfo)
        astronomy = forecast["astronomy"][0]
        astronomy.update({
            "moon_phase": name,
            "moon_short": short_name,
            "moon_icon": icon,
            "moon_illumination": illumination,
            "moonrise": moonrise_clock,
            "moonset": moonset_clock,
            "solstice": next_solstice(day, latitude, tzinfo),
        })
        for name, calculate in (("blue_hour", blue_hour), ("golden_hour", golden_hour)):
            for period, direction in (("morning", SunDirection.RISING), ("evening", SunDirection.SETTING)):
                astronomy[f"{name}_{period}"] = event_clock(calculate, observer, day, tzinfo, direction=direction)
    return weather
