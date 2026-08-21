#!/usr/bin/env python

import argparse
import json
import os
import sys
import tempfile
import time
from datetime import datetime

# Add the parent hypr lib directory to path so we can import pyutils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyutils.pip_env as pip_env
from pyutils.shell_env import load_shell_assignments

pip_env.ensure_managed_interpreter()

try:
    requests = pip_env.v_import("requests")
except ImportError:
    requests = None

# Cache for weather codes loaded from JSON
_WEATHER_CODES_CACHE = None


def _load_weather_codes():
    """Load weather codes from JSON file"""
    global _WEATHER_CODES_CACHE
    if _WEATHER_CODES_CACHE is not None:
        return _WEATHER_CODES_CACHE

    json_file = os.path.join(os.path.dirname(__file__), "weather_codes.json")
    try:
        with open(json_file, "r", encoding="utf-8") as f:
            _WEATHER_CODES_CACHE = json.load(f)
    except Exception:
        # Fallback if JSON file can't be loaded
        _WEATHER_CODES_CACHE = {"default": "󰖐"}

    return _WEATHER_CODES_CACHE


def get_weather_icon_from_code(weather_code):
    """Get Nerd Font icon for a weather code"""
    codes = _load_weather_codes()
    return codes.get(str(weather_code), codes.get("default", "󰖐"))


# Weather data cache
CACHE_DIR = os.path.join(os.getenv("HOME"), ".cache/wttr")
WEATHER_DATA_CACHE = os.path.join(CACHE_DIR, "weather_data.json")
CACHE_EXPIRY = 3600  # 1 hour in seconds


def is_cache_valid():
    """Check if cache exists and is not expired"""
    if not os.path.exists(WEATHER_DATA_CACHE):
        return False
    try:
        cache_age = time.time() - os.path.getmtime(WEATHER_DATA_CACHE)
        return cache_age < CACHE_EXPIRY
    except OSError:
        return False


def load_cache():
    """Load weather data from cache"""
    try:
        with open(WEATHER_DATA_CACHE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def save_cache(weather_data):
    """Save weather data to cache.

    Written through a temp file and renamed: the bar watches this path, and a
    plain write lets it read a half-finished file and report a parse error.
    """
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        handle, staging = tempfile.mkstemp(dir=CACHE_DIR)
        with os.fdopen(handle, "w", encoding="utf-8") as f:
            json.dump(weather_data, f)
        os.replace(staging, WEATHER_DATA_CACHE)
    except Exception as e:
        print(f"Warning: Failed to save cache: {e}", file=sys.stderr)


# Open-Meteo reports WMO codes; the shared icon table is keyed by the WWO codes
# wttr.in uses, so each entry carries the nearest WWO equivalent and its text.
WMO_CONDITIONS = {
    0: ("113", "Clear"),
    1: ("116", "Partly cloudy"),
    2: ("116", "Partly cloudy"),
    3: ("119", "Overcast"),
    45: ("143", "Fog"),
    48: ("260", "Freezing fog"),
    51: ("266", "Light drizzle"),
    53: ("266", "Drizzle"),
    55: ("293", "Heavy drizzle"),
    56: ("281", "Freezing drizzle"),
    57: ("284", "Heavy freezing drizzle"),
    61: ("293", "Light rain"),
    63: ("296", "Rain"),
    65: ("308", "Heavy rain"),
    66: ("311", "Freezing rain"),
    67: ("314", "Heavy freezing rain"),
    71: ("323", "Light snow"),
    73: ("332", "Snow"),
    75: ("338", "Heavy snow"),
    77: ("350", "Snow grains"),
    80: ("353", "Light showers"),
    81: ("356", "Showers"),
    82: ("359", "Heavy showers"),
    85: ("368", "Light snow showers"),
    86: ("371", "Heavy snow showers"),
    95: ("386", "Thunderstorm"),
    96: ("392", "Thunderstorm with hail"),
    99: ("395", "Heavy thunderstorm with hail"),
}

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
OPEN_METEO_GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"


def temp_pair(celsius):
    return str(round(celsius)), str(round(celsius * 9 / 5 + 32))


def wind_pair(kmph):
    return str(round(kmph)), str(round(kmph * 0.621371))


def clock_12h(stamp):
    try:
        return datetime.fromisoformat(stamp).strftime("%I:%M %p")
    except (TypeError, ValueError):
        return ""


def parse_coordinates(location):
    parts = str(location).split(",")
    if len(parts) != 2:
        return None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None


def geocode_candidates(name, count=5):
    """Places matching a name. Open-Meteo only accepts coordinates, so a name
    has to be resolved first, and ambiguous names ("Springfield") need the
    caller to choose."""
    try:
        response = requests.get(
            OPEN_METEO_GEOCODE_URL,
            params={"name": name.replace("_", " "), "count": count, "format": "json"},
            timeout=10,
        )
        response.raise_for_status()
        return response.json().get("results") or []
    except (requests.RequestException, json.JSONDecodeError, AttributeError):
        return []


def geocode(name):
    results = geocode_candidates(name, count=1)
    if not results:
        return None
    top = results[0]
    return (
        top["latitude"],
        top["longitude"],
        top.get("name", ""),
        top.get("country", ""),
    )


def annotate_day_icons(weather):
    """Attach a forecast glyph to each day, whichever provider supplied it."""
    for day in weather.get("weather", []):
        code = day.get("weatherCode")
        if not code:
            hours = day.get("hourly") or []
            midday = hours[len(hours) // 2] if hours else {}
            code = midday.get("weatherCode")
        if code:
            day["icon"] = get_weather_icon_from_code(code)
    return weather


def to_wttr_shape(payload, city, country):
    """Rewrite an Open-Meteo response into the j1 layout the getters expect."""
    current = payload["current"]
    daily = payload["daily"]

    code, description = WMO_CONDITIONS.get(
        current.get("weather_code"), ("119", "Unknown")
    )
    temp_c, temp_f = temp_pair(current["temperature_2m"])
    feels_c, feels_f = temp_pair(current["apparent_temperature"])
    wind_kmph, wind_miles = wind_pair(current["wind_speed_10m"])

    hourly = payload.get("hourly", {})

    # dew point and visibility only come per hour; take the one covering "now"
    stamps = hourly.get("time", [])
    now = str(current.get("time", ""))[:13]
    hour_index = next((i for i, stamp in enumerate(stamps) if stamp[:13] == now), 0)

    def at_hour(key):
        series = hourly.get(key) or []
        return series[hour_index] if hour_index < len(series) else None

    dew_c, dew_f = temp_pair(at_hour("dew_point_2m") or 0)
    metres = at_hour("visibility")

    rain_by_date = {}
    for stamp, chance in zip(
        hourly.get("time", []), hourly.get("precipitation_probability", [])
    ):
        rain_by_date.setdefault(stamp[:10], []).append(
            {"chanceofrain": str(chance or 0)}
        )

    days = []
    for index, date in enumerate(daily["time"]):
        high_c, high_f = temp_pair(daily["temperature_2m_max"][index])
        low_c, low_f = temp_pair(daily["temperature_2m_min"][index])
        day_code, _ = WMO_CONDITIONS.get(
            (daily.get("weather_code") or [None] * (index + 1))[index], ("119", "")
        )
        days.append(
            {
                "date": date,
                "weatherCode": day_code,
                "maxtempC": high_c,
                "maxtempF": high_f,
                "mintempC": low_c,
                "mintempF": low_f,
                "astronomy": [
                    {
                        "sunrise": clock_12h(daily["sunrise"][index]),
                        "sunset": clock_12h(daily["sunset"][index]),
                    }
                ],
                "hourly": rain_by_date.get(date, []),
                "chanceofrain": str(max(
                    (int(hour["chanceofrain"]) for hour in rain_by_date.get(date, [])),
                    default=0,
                )),
            }
        )

    return {
        "current_condition": [
            {
                "temp_C": temp_c,
                "temp_F": temp_f,
                "FeelsLikeC": feels_c,
                "FeelsLikeF": feels_f,
                "windspeedKmph": wind_kmph,
                "windspeedMiles": wind_miles,
                "humidity": str(current.get("relative_humidity_2m", "")),
                "uvIndex": str(round(current.get("uv_index") or 0)),
                "cloudcover": str(round(current.get("cloud_cover") or 0)),
                "pressure": str(round(current.get("surface_pressure") or 0)),
                "DewPointC": dew_c,
                "DewPointF": dew_f,
                "visibility": "" if metres is None else str(round(metres / 1000)),
                "weatherCode": code,
                "weatherDesc": [{"value": description}],
            }
        ],
        "weather": days,
        "nearest_area": [
            {
                "areaName": [{"value": city}],
                "country": [{"value": country}],
            }
        ],
    }


def fetch_open_meteo(location, city, country):
    point = parse_coordinates(location)
    if point is None:
        resolved = geocode(location)
        if resolved is None:
            return None
        latitude, longitude, city, country = resolved
    else:
        latitude, longitude = point

    try:
        response = requests.get(
            OPEN_METEO_URL,
            params={
                "latitude": latitude,
                "longitude": longitude,
                "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,uv_index,cloud_cover,surface_pressure",
                "daily": "temperature_2m_max,temperature_2m_min,sunrise,sunset,weather_code",
                "hourly": "precipitation_probability,dew_point_2m,visibility",
                "timezone": "auto",
                "forecast_days": 3,
            },
            timeout=10,
        )
        response.raise_for_status()
        return to_wttr_shape(response.json(), city, country)
    except (requests.RequestException, json.JSONDecodeError, KeyError, TypeError):
        return None


def read_location_cache():
    """Open-Meteo has no reverse geocoding, so this names a place given only
    coordinates."""
    path = os.path.join(os.getenv("HOME"), ".cache/wttr/location.cache")
    values = {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                key, separator, value = line.partition("=")
                if separator:
                    values[key.strip()] = value.strip()
    except OSError:
        pass
    return values.get("CITY", ""), values.get("COUNTRY", "")


def fetch_wttr(location):
    try:
        response = requests.get(
            f"https://wttr.in/{location}?format=j1",
            timeout=10,
            headers={"User-Agent": "Mozilla/5.0"},
        )
        response.raise_for_status()
        return response.json()
    except (requests.RequestException, json.JSONDecodeError):
        return None


parser = argparse.ArgumentParser()
parser.add_argument(
    "-m",
    "--minmax",
    action="store_true",
    help="Show min/max temperature instead of current",
)
parser.add_argument(
    "-s",
    "--sunrise",
    action="store_true",
    help="Show sunrise time",
)
parser.add_argument(
    "-S",
    "--sunset",
    action="store_true",
    help="Show sunset time",
)
parser.add_argument(
    "-f",
    "--force",
    action="store_true",
    help="Force refresh cache (ignore cached data)",
)
parser.add_argument(
    "-A",
    "--alt",
    action="store_true",
    help="Join fields horizontally with a space instead of stacking with newlines",
)
parser.add_argument("--temps-only", action="store_true", help="Only show min/max temperatures")
parser.add_argument(
    "--search",
    metavar="QUERY",
    help="Print matching places as JSON and exit, for a location picker",
)
args = parser.parse_args()
field_sep = " " if args.alt else "\n"


def load_env_file(filepath):
    try:
        for key, value in load_shell_assignments(filepath).items():
            os.environ[key] = value
    except Exception:
        pass  # shhh


def env_flag(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in ("true", "1", "t", "y", "yes")


def resolve_theme_coordinates():
    latitude = os.getenv("AUTO_THEME_LATITUDE", "").strip()
    longitude = os.getenv("AUTO_THEME_LONGITUDE", "").strip()
    if not latitude or not longitude:
        return ""
    if latitude.lower() == "auto" or longitude.lower() == "auto":
        return ""
    return f"{latitude},{longitude}"


def get_weather_icon(weatherinstance):
    return get_weather_icon_from_code(weatherinstance["weatherCode"])


def get_description(weatherinstance):
    return weatherinstance["weatherDesc"][0]["value"]


def get_temperature(weatherinstance):
    if temp_unit == "c":
        return weatherinstance["temp_C"] + "°C"

    return weatherinstance["temp_F"] + "°F"


def get_feels_like(weatherinstance):
    if temp_unit == "c":
        return weatherinstance["FeelsLikeC"] + "°C"

    return weatherinstance["FeelsLikeF"] + "°F"


def get_wind_value(weatherinstance):
    if windspeed_unit == "km/h":
        return weatherinstance["windspeedKmph"]

    return weatherinstance["windspeedMiles"]


def get_wind_speed(weatherinstance):
    unit = "Km/h" if windspeed_unit == "km/h" else "Mph"
    return get_wind_value(weatherinstance) + unit


def get_max_temp(day):
    if temp_unit == "c":
        return day["maxtempC"] + "°C"

    return day["maxtempF"] + "°F"


def get_min_temp(day):
    if temp_unit == "c":
        return day["mintempC"] + "°C"

    return day["mintempF"] + "°F"


def get_sunrise(day, force_24h=False):
    return get_timestamp(day["astronomy"][0]["sunrise"], force_24h)


def get_sunset(day, force_24h=False):
    return get_timestamp(day["astronomy"][0]["sunset"], force_24h)


def get_city_name(weather):
    return weather["nearest_area"][0]["areaName"][0]["value"]


def get_country_name(weather):
    return weather["nearest_area"][0]["country"][0]["value"]


def get_timestamp(time_str, force_24h=False):
    if force_24h or time_format == "24h":
        return datetime.strptime(time_str, "%I:%M %p").strftime("%H:%M")

    return time_str


def split_time_parts(time_str):
    time_str = time_str.strip()
    if " " in time_str:
        time_main, suffix = time_str.split(" ", 1)
    else:
        time_main, suffix = time_str, ""
    if ":" in time_main:
        hour, minute = time_main.split(":", 1)
    else:
        hour, minute = time_main, ""
    return hour, minute, suffix


state_home = os.environ.get("XDG_STATE_HOME") or os.path.join(
    os.environ.get("HOME"), ".local", "state"
)
load_env_file(os.path.join(state_home, "hypr", "staterc"))
load_env_file(os.path.join(state_home, "hypr", "env-overrides"))

temp_unit = os.getenv(
    "WEATHER_TEMPERATURE_UNIT", "c"
).lower()  # c or f            (default: c)
time_format = os.getenv(
    "WEATHER_TIME_FORMAT", "12h"
).lower()  # 12h or 24h        (default: 12h)
windspeed_unit = os.getenv(
    "WEATHER_WINDSPEED_UNIT", "km/h"
).lower()  # km/h or mph       (default: Km/h)
show_icon = os.getenv("WEATHER_SHOW_ICON", "True").lower() in (
    "true",
    "1",
    "t",
    "y",
    "yes",
)  # True or False     (default: True)
show_location = os.getenv("WEATHER_SHOW_LOCATION", "False").lower() in (
    "true",
    "1",
    "t",
    "y",
    "yes",
)  # True or False     (default: False)
show_today_details = os.getenv("WEATHER_SHOW_TODAY_DETAILS", "True").lower() in (
    "true",
    "1",
    "t",
    "y",
    "yes",
)  # True or False     (default: True)
get_location = os.getenv("WEATHER_LOCATION", "").replace(
    " ", "_"
)  # Name of the location to get the weather from (default: '')
allow_auto_geolocation = env_flag("WEATHER_ALLOW_AUTO_GEOLOCATION", False)

# Prefer explicit theme coordinates when WEATHER_LOCATION is unset.
if not get_location:
    get_location = resolve_theme_coordinates().replace(" ", "_")

cached_city, cached_country = read_location_cache()

# a picked coordinate has no name of its own; the label recorded with it wins
pinned_label = os.getenv("WEATHER_LOCATION_LABEL", "").strip()
if pinned_label:
    label_city, _, label_country = pinned_label.partition(", ")
    cached_city, cached_country = label_city, label_country or cached_country

# If no explicit location is set, try to read from cached location
if not get_location and cached_city:
    get_location = cached_city.replace(" ", "_")

# Optional network geolocation fallback
if not get_location and allow_auto_geolocation and requests is not None:
    try:
        response = requests.get("https://ipinfo.io", timeout=3)
        data = response.json()
        loc = data.get("loc")  # e.g., "48.8566,2.3522"
        city = data.get("city")
        get_location = (loc or city or "").replace(" ", "_")
    except Exception:
        get_location = ""

# Final fallback to Paris if all else fails
if not get_location:
    get_location = "Paris"

if temp_unit not in ("c", "f"):
    temp_unit = "c"
if time_format not in ("12h", "24h"):
    time_format = "12h"
if windspeed_unit not in ("km/h", "mph"):
    windspeed_unit = "km/h"

if args.search:
    # a picker needs the coordinates plus enough to tell the matches apart
    print(json.dumps([
        {
            "name": place.get("name", ""),
            "region": place.get("admin1", ""),
            "country": place.get("country", ""),
            "latitude": place.get("latitude"),
            "longitude": place.get("longitude"),
        }
        for place in geocode_candidates(args.search)
        if place.get("latitude") is not None
    ]))
    sys.exit(0)

data = {}
weather = None

if not args.force and is_cache_valid():
    weather = load_cache()

if weather is None:
    if requests is None:
        print(
            "Error: Missing optional Python dependency 'requests'. "
            "Install it explicitly with `hyprshell pip install requests`.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Open-Meteo first: wttr.in has served identical bogus readings for every
    # location at times, and it stays useful as a fallback.
    weather = fetch_open_meteo(get_location, cached_city, cached_country)
    if weather is None:
        weather = fetch_wttr(get_location)

    if weather is None:
        weather = load_cache()
        if weather is None:
            print("Error: Failed to get weather data", file=sys.stderr)
            sys.exit(1)
    else:
        save_cache(annotate_day_icons(weather))

current_weather = weather["current_condition"][0]

if args.minmax:
    today = weather["weather"][0]
    min_temp = get_min_temp(today).split("°")[0]
    max_temp = get_max_temp(today).split("°")[0]
    data["text"] = f"{max_temp}{field_sep}{min_temp}"
    if not args.temps_only:
        max_rain_chance = min(
            max(int(hour.get("chanceofrain", 0)) for hour in today["hourly"]), 99
        )
        data["text"] += f"{field_sep}{max_rain_chance:2d}󱢋{field_sep}{get_wind_value(current_weather)}"
elif args.sunrise:
    today = weather["weather"][0]
    sunrise = get_sunrise(today, args.alt)
    sunrise_h, sunrise_m, _ = split_time_parts(sunrise)
    data["text"] = f" {sunrise}" if args.alt else f"  \n{sunrise_h}:\n{sunrise_m} "
elif args.sunset:
    today = weather["weather"][0]
    sunset = get_sunset(today, args.alt)
    sunset_h, sunset_m, _ = split_time_parts(sunset)
    data["text"] = f" {sunset}" if args.alt else f"  \n {sunset_h}\n:{sunset_m}"
else:
    data["text"] = get_feels_like(current_weather)
    if show_icon:
        data["text"] = field_sep + data["text"]
        data["text"] = f"{get_weather_icon(current_weather)}" + data["text"]
    if show_location:
        data["text"] += f" | {get_city_name(weather)}, {get_country_name(weather)}"

    # waybar tooltip
    data["tooltip"] = ""
    if show_today_details:
        today = weather["weather"][0]
        data["tooltip"] += (
            f"<b>{get_description(current_weather)} {get_temperature(current_weather)}</b>\n"
        )
        data["tooltip"] += (
            f"Location: {get_city_name(weather)}, {get_country_name(weather)}\n"
        )
        data["tooltip"] += f"Feels like: {get_feels_like(current_weather)}\n"
        data["tooltip"] += f"Wind: {get_wind_speed(current_weather)}\n"
        data["tooltip"] += f"Humidity: {current_weather['humidity']}%\n"
        data["tooltip"] += f"Sunrise: {get_sunrise(today)}\n"
        data["tooltip"] += f"Sunset: {get_sunset(today)}\n"
        data["tooltip"] += f"Max|Min: {get_max_temp(today)} | {get_min_temp(today)}"


print(json.dumps(data))
