#!/usr/bin/env python3
import json
import os
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import NamedTuple, Optional
from zoneinfo import ZoneInfo

from auto_theme_state import load_state_env
from pyutils.xdg_base_dirs import xdg_config_home

try:
    from astral import LocationInfo
    from astral.sun import sun
    ASTRAL_AVAILABLE = True
except ImportError:
    ASTRAL_AVAILABLE = False
    print("Warning: astral not installed, sunrise/sunset calculation disabled")

CONFIG_FILE = xdg_config_home() / "hypr/auto_theme.conf"
STATE_LOCATION_ENV_KEYS = {
    "AUTO_THEME_LATITUDE": "latitude",
    "AUTO_THEME_LONGITUDE": "longitude",
    "AUTO_THEME_TIMEZONE": "timezone",
}

DEFAULT_CONFIG = {
    "latitude": "auto",
    "longitude": "auto",
    "timezone": "auto",
    "allow_auto_geolocation": False,
    "daylight_inset_minutes": 30,
    "control_hyprland": True,
    "manual_override_minutes": 120,
}


class DaylightWindow(NamedTuple):
    starts_at: datetime
    ends_at: datetime


def load_config(config_file: Path = CONFIG_FILE) -> dict:
    config = DEFAULT_CONFIG.copy()
    if config_file.exists():
        try:
            content = config_file.read_text().strip()
            if content.startswith("{"):
                user_config = json.loads(content)
            else:
                user_config = {}
                for line in content.split("\n"):
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        key = key.strip()
                        value = value.strip()
                        if value.lower() in ("true", "false"):
                            value = value.lower() == "true"
                        elif value.replace(".", "").replace("-", "").isdigit():
                            value = float(value) if "." in value else int(value)
                        user_config[key] = value
            config.update(user_config)
        except Exception as exc:
            print(f"Warning: Failed to load config: {exc}")
    return config


def apply_location_overrides_from_state(config: dict) -> None:
    state_env = load_state_env()
    for env_key, config_key in STATE_LOCATION_ENV_KEYS.items():
        raw_value = state_env.get(env_key)
        if raw_value is None:
            raw_value = os.environ.get(env_key)
        if raw_value is None:
            continue
        value = raw_value.strip()
        if not value:
            continue
        if value.lower() == "auto":
            config[config_key] = "auto"
            continue
        if config_key in ("latitude", "longitude"):
            try:
                config[config_key] = float(value)
            except ValueError:
                print(f"Warning: Invalid {env_key} value '{value}', ignoring")
            continue
        config[config_key] = value


def resolve_location_settings_into(config: dict) -> None:
    apply_location_overrides_from_state(config)
    if (
        config.get("latitude") != "auto"
        and config.get("longitude") != "auto"
        and config.get("timezone") != "auto"
    ):
        return

    if not bool(config.get("allow_auto_geolocation", False)):
        print(
            "Warning: Auto geolocation is disabled. "
            "Set allow_auto_geolocation=true to enable network-based location lookup."
        )
        if config.get("latitude") == "auto":
            config["latitude"] = 0
        if config.get("longitude") == "auto":
            config["longitude"] = 0
        if config.get("timezone") == "auto":
            config["timezone"] = "UTC"
        return

    try:
        import urllib.request

        with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as resp:
            data = json.loads(resp.read().decode())
        if data.get("error"):
            raise ValueError(f"Geolocation failed: {data.get('error')}")

        loc_raw = str(data.get("loc", "")).strip()
        lat = lon = None
        if "," in loc_raw:
            lat_raw, lon_raw = loc_raw.split(",", 1)
            lat = float(lat_raw.strip())
            lon = float(lon_raw.strip())

        if config.get("latitude") == "auto":
            if lat is None:
                raise ValueError("Geolocation response missing latitude")
            config["latitude"] = lat
        if config.get("longitude") == "auto":
            if lon is None:
                raise ValueError("Geolocation response missing longitude")
            config["longitude"] = lon
        if config.get("timezone") == "auto":
            config["timezone"] = data.get("timezone", "UTC") or "UTC"

        print(f"Auto-detected location: {data.get('city', 'Unknown')}, {data.get('country', 'Unknown')}")
        print(f"  Coordinates: {config['latitude']}, {config['longitude']}")
        print(f"  Timezone: {config['timezone']}")
    except Exception as exc:
        print(f"Warning: Failed to auto-detect location: {exc}")
        print("Using fallback location (UTC, equator)")
        if config.get("latitude") == "auto":
            config["latitude"] = 0
        if config.get("longitude") == "auto":
            config["longitude"] = 0
        if config.get("timezone") == "auto":
            config["timezone"] = "UTC"


# The day assumed when astral is missing or cannot place the sun.
FALLBACK_SUNRISE = time(6, 0)
FALLBACK_SUNSET = time(18, 0)


def astral_sun_times(config: dict, target_date: date) -> Optional[tuple[datetime, datetime]]:
    try:
        location = LocationInfo(
            latitude=config["latitude"],
            longitude=config["longitude"],
            timezone=config["timezone"],
        )
        tz_name = str(config.get("timezone", "UTC") or "UTC")
        try:
            tz = ZoneInfo(tz_name)
        except Exception:
            tz = ZoneInfo("UTC")
        sun_times = sun(location.observer, date=target_date, tzinfo=tz)
        return sun_times["sunrise"].astimezone().replace(tzinfo=None), sun_times["sunset"].astimezone().replace(tzinfo=None)
    except Exception as exc:
        print(f"Warning: Failed to calculate sun times: {exc}")
        return None


def daylight_window(config: dict, target_date: Optional[date] = None) -> DaylightWindow:
    if target_date is None:
        target_date = datetime.now().date()
    sun_times = astral_sun_times(config, target_date) if ASTRAL_AVAILABLE else None
    sunrise, sunset = sun_times or (datetime.combine(target_date, FALLBACK_SUNRISE), datetime.combine(target_date, FALLBACK_SUNSET))
    inset = timedelta(minutes=config["daylight_inset_minutes"])
    return DaylightWindow(sunrise + inset, sunset - inset)


def next_daylight_boundary(config: dict, now: datetime) -> datetime:
    today = daylight_window(config, now.date())
    if now < today.starts_at:
        return today.starts_at
    if now < today.ends_at:
        return today.ends_at
    return daylight_window(config, (now + timedelta(days=1)).date()).starts_at
