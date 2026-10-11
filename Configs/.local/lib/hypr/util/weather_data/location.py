import json
import os

from pyutils.shell_env import load_shell_assignments
from pyutils.xdg_base_dirs import xdg_state_home
from .cache import read_location_labels
from .http import LOCATION_TIMEOUT_SECONDS, REQUEST_TIMEOUT_SECONDS, requests_client

OPEN_METEO_GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"


def parse_coordinates(location):
    parts = str(location).split(",")
    if len(parts) != 2:
        return None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None


def geocode_candidates(name, count=5):
    """Open-Meteo only accepts coordinates, so a name has to be resolved first, and
    ambiguous names ("Springfield") need the caller to choose."""
    requests = requests_client()
    if requests is None:
        return []
    try:
        response = requests.get(
            OPEN_METEO_GEOCODE_URL,
            params={"name": name.replace("_", " "), "count": count, "format": "json"},
            timeout=REQUEST_TIMEOUT_SECONDS,
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


def load_env_file(filepath):
    try:
        for key, value in load_shell_assignments(filepath).items():
            os.environ[key] = value
    except (OSError, UnicodeError):
        pass


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


def load_weather_environment():
    state_home = xdg_state_home()
    load_env_file(state_home / "hypr/staterc")
    load_env_file(state_home / "hypr/env-overrides")


def resolve_weather_location():
    location = os.getenv("WEATHER_LOCATION", "").replace(" ", "_")
    if not location:
        location = resolve_theme_coordinates().replace(" ", "_")
    city, country = read_location_labels()
    pinned_label = os.getenv("WEATHER_LOCATION_LABEL", "").strip()
    if pinned_label:
        city, _, label_country = pinned_label.partition(", ")
        country = label_country or country
    if not location and city:
        location = city.replace(" ", "_")
    if not location and env_flag("WEATHER_ALLOW_AUTO_GEOLOCATION"):
        requests = requests_client()
        if requests is not None:
            try:
                data = requests.get("https://ipinfo.io", timeout=LOCATION_TIMEOUT_SECONDS).json()
                location = (data.get("loc") or data.get("city") or "").replace(" ", "_")
            except Exception:
                location = ""
    return location or "Paris", city, country
