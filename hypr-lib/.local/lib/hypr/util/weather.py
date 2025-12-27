#!/usr/bin/env python

import argparse
import json
import os
import sys
import time
from datetime import datetime

# Add the parent hypr lib directory to path so we can import pyutils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyutils.pip_env as pip_env

pip_env.v_import(
    "requests"
)  # fetches the module by name // does `pip install --update requests` under the hood
import requests  # noqa: E402

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
    """Save weather data to cache"""
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(WEATHER_DATA_CACHE, "w", encoding="utf-8") as f:
            json.dump(weather_data, f)
    except Exception as e:
        print(f"Warning: Failed to save cache: {e}", file=sys.stderr)


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
args = parser.parse_args()


### Functions ###
def load_env_file(filepath):
    try:
        with open(filepath, encoding="utf-8") as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    if line.startswith("export "):
                        line = line[len("export ") :]
                    key, value = line.strip().split("=", 1)
                    os.environ[key] = value.strip('"')
    except Exception:
        pass  # shhh


def get_weather_icon(weatherinstance):
    return get_weather_icon_from_code(weatherinstance["weatherCode"])


def get_description(weatherinstance):
    return weatherinstance["weatherDesc"][0]["value"]


def get_temperature(weatherinstance):
    if temp_unit == "c":
        return weatherinstance["temp_C"] + "°C"

    return weatherinstance["temp_F"] + "°F"


def get_temperature_hour(weatherinstance):
    if temp_unit == "c":
        return weatherinstance["tempC"] + "°C"

    return weatherinstance["tempF"] + "°F"


def get_feels_like(weatherinstance):
    if temp_unit == "c":
        return weatherinstance["FeelsLikeC"] + "°C"

    return weatherinstance["FeelsLikeF"] + "°F"


def get_wind_speed(weatherinstance):
    if windspeed_unit == "km/h":
        return weatherinstance["windspeedKmph"] + "Km/h"

    return weatherinstance["windspeedMiles"] + "Mph"


def get_max_temp(day):
    if temp_unit == "c":
        return day["maxtempC"] + "°C"

    return day["maxtempF"] + "°F"


def get_min_temp(day):
    if temp_unit == "c":
        return day["mintempC"] + "°C"

    return day["mintempF"] + "°F"


def get_sunrise(day):
    return get_timestamp(day["astronomy"][0]["sunrise"])


def get_sunset(day):
    return get_timestamp(day["astronomy"][0]["sunset"])


def get_city_name(weather):
    return weather["nearest_area"][0]["areaName"][0]["value"]


def get_country_name(weather):
    return weather["nearest_area"][0]["country"][0]["value"]


def format_time(time):
    return (time.replace("00", "")).ljust(3)


def format_temp(temp):
    if temp[0] != "-":
        temp = " " + temp
    return temp.ljust(5)


def get_timestamp(time_str):
    if time_format == "24h":
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


def format_chances(hour):
    chances = {
        "chanceoffog": "Fog",
        "chanceoffrost": "Frost",
        "chanceofovercast": "Overcast",
        "chanceofrain": "Rain",
        "chanceofsnow": "Snow",
        "chanceofsunshine": "Sunshine",
        "chanceofthunder": "Thunder",
        "chanceofwindy": "Wind",
    }

    conditions = [
        f"{chances[event]} {hour[event]}%"
        for event in chances
        if int(hour.get(event, 0)) > 0
    ]
    return ", ".join(conditions)


### Variables ###
load_env_file(
    os.path.join(os.environ.get("HOME"), ".rlocal", "state", "hypr", "staterc")
)
load_env_file(os.path.join(os.environ.get("HOME"), ".local", "state", "hypr", "config"))

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
try:
    FORECAST_DAYS = int(
        os.getenv("WEATHER_FORECAST_DAYS", "3")
    )  # Number of days to show the forecast for (default: 3)
except ValueError:
    FORECAST_DAYS = 3
get_location = os.getenv("WEATHER_LOCATION", "").replace(
    " ", "_"
)  # Name of the location to get the weather from (default: '')

# Parse the location to wttr.in format (snake_case)
if not get_location:
    try:
        response = requests.get("https://ipinfo.io", timeout=3)
        data = response.json()
        loc = data.get("loc")  # e.g., "48.8566,2.3522"
        city = data.get("city")
        # prefer coordinates if available, fallback to city
        get_location = loc or city or ""
        get_location = get_location.replace(" ", "_")
    except Exception:
        get_location = ""

# If location detection failed, try to read from cached location
if not get_location:
    location_cache = os.path.join(os.getenv("HOME"), ".cache/wttr/location.cache")
    if os.path.exists(location_cache):
        try:
            with open(location_cache, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("CITY="):
                        city = line.split("=", 1)[1].strip()
                        if city:
                            get_location = city.replace(" ", "_")
                            break
        except Exception:
            pass

# Final fallback to Paris if all else fails
if not get_location:
    get_location = "Paris"

# Check if the variables are set correctly
if temp_unit not in ("c", "f"):
    TEMP_UNIT = "c"
if time_format not in ("12h", "24h"):
    TIME_FORMAT = "12h"
if windspeed_unit not in ("km/h", "mph"):
    WINDSPEED_UINT = "km/h"
if FORECAST_DAYS not in range(4):
    FORECAST_DAYS = 3

### Main Logic ###
data = {}
weather = None

# Try to load from cache first (unless force flag is set)
if not args.force and is_cache_valid():
    weather = load_cache()

# If cache is invalid, doesn't exist, or force refresh, fetch from API
if weather is None:
    URL = f"https://wttr.in/{get_location}?format=j1"
    headers = {"User-Agent": "Mozilla/5.0"}
    try:
        response = requests.get(URL, timeout=10, headers=headers)
        weather = response.json()
        # Save to cache for future use
        save_cache(weather)
    except (requests.RequestException, json.decoder.JSONDecodeError) as e:
        print(f"Error: Failed to get weather data: {e}", file=sys.stderr)
        sys.exit(1)

current_weather = weather["current_condition"][0]

# Get the data to display
# waybar text

if args.minmax:
    # Show min/max temp for today
    today = weather["weather"][0]
    max_rain_chance = min(
        max(int(hour.get("chanceofrain", 0)) for hour in today["hourly"]), 99
    )
    min_temp = get_min_temp(today).split("°")[0]
    max_temp = get_max_temp(today).split("°")[0]
    data["text"] = (
        f"{max_temp}\n{min_temp}\n{max_rain_chance:2d}󱢋\n{get_wind_speed(current_weather).split('K')[0]}"
    )
elif args.sunrise:
    # Show sunrise time
    today = weather["weather"][0]
    sunrise = get_sunrise(today)
    sunset = get_sunset(today)
    sunrise_h, sunrise_m, sunrise_period = split_time_parts(sunrise)
    sunrise_suffix = f"\n{sunrise_period}" if sunrise_period else ""
    data["text"] = f"  \n{sunrise_h}:\n{sunrise_m}|"
elif args.sunset:
    # Show sunset time
    today = weather["weather"][0]
    sunrise = get_sunrise(today)
    sunset = get_sunset(today)
    sunset_h, sunset_m, sunset_period = split_time_parts(sunset)
    sunset_suffix = f"\n{sunset_period}" if sunset_period else ""
    data["text"] = f"  \n|{sunset_h}\n:{sunset_m}"
else:
    data["text"] = get_feels_like(current_weather)
    if show_icon:
        data["text"] = "\n" + data["text"]
        data["text"] = f"{get_weather_icon(current_weather)}" + data["text"]
    if show_location:
        data["text"] += f" | {get_city_name(weather)}, {get_country_name(weather)}"

    # waybar tooltip
    data["tooltip"] = ""
    if show_today_details:
        data["tooltip"] += (
            f"<b>{get_description(current_weather)} {get_temperature(current_weather)}</b>\n"
        )
        data["tooltip"] += f"Feels like: {get_feels_like(current_weather)}\n"
        data["tooltip"] += (
            f"Location: {get_city_name(weather)}, {get_country_name(weather)}\n"
        )
        data["tooltip"] += f"Wind: {get_wind_speed(current_weather)}\n"
        data["tooltip"] += f"Humidity: {current_weather['humidity']}%\n"


print(json.dumps(data))
