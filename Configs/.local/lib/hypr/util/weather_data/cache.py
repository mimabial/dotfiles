import json
import os
import tempfile
import time
import sys
from pathlib import Path

WEATHER_CACHE_DIR = Path.home() / ".cache/wttr"
WEATHER_CACHE_PATH = WEATHER_CACHE_DIR / "weather_data.json"
LOCATION_CACHE_PATH = WEATHER_CACHE_DIR / "location.cache"
WEATHER_CACHE_MAX_AGE_SECONDS = 3600


def weather_cache_is_fresh():
    if not os.path.exists(WEATHER_CACHE_PATH):
        return False
    try:
        cache_age = time.time() - os.path.getmtime(WEATHER_CACHE_PATH)
        return cache_age < WEATHER_CACHE_MAX_AGE_SECONDS
    except OSError:
        return False


def read_weather_cache():
    try:
        with open(WEATHER_CACHE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def write_weather_cache(weather_data):
    """Written through a temp file and renamed: the bar watches this path, and a
    plain write lets it read a half-finished file and report a parse error."""
    staging = None
    try:
        os.makedirs(WEATHER_CACHE_DIR, exist_ok=True)
        handle, staging = tempfile.mkstemp(dir=WEATHER_CACHE_DIR)
        with os.fdopen(handle, "w", encoding="utf-8") as f:
            json.dump(weather_data, f)
        os.replace(staging, WEATHER_CACHE_PATH)
        staging = None
    except Exception as e:
        print(f"Warning: Failed to save cache: {e}", file=sys.stderr)
    finally:
        if staging is not None:
            Path(staging).unlink(missing_ok=True)

def read_location_labels():
    """Open-Meteo has no reverse geocoding, so this names a place given only
    coordinates."""
    path = LOCATION_CACHE_PATH
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


def invalidate_weather_cache():
    WEATHER_CACHE_PATH.unlink(missing_ok=True)
