#!/usr/bin/env python3
import fcntl
import json
import os
import shutil
import sys
import tempfile
from contextlib import contextmanager
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Optional
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils.lock_paths import runtime_root
from pyutils.shell_env import load_shell_assignments, shell_quote_value
from pyutils.xdg_base_dirs import xdg_cache_home, xdg_config_home, xdg_state_home

try:
    from astral import LocationInfo
    from astral.sun import sun
    ASTRAL_AVAILABLE = True
except ImportError:
    ASTRAL_AVAILABLE = False
    print("Warning: astral not installed, sunrise/sunset calculation disabled")

CONFIG_FILE = xdg_config_home() / "hypr/auto_theme.conf"
STATE_FILE = xdg_state_home() / "hypr/auto_theme_state.json"
STATE_TARGETS = ("staterc", "env-overrides", "color_variant")
TMPDIR_PATH = Path(os.environ.get("TMPDIR", "/tmp"))
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
    "watchdog_interval_seconds": 60,
    "daylight_inset_minutes": 30,
    "control_hyprland": True,
    "manual_override_minutes": 120,
}


def active_palette_file() -> Path:
    return xdg_state_home() / "hypr" / "active-palette.json"


def wallpaper_state_file() -> Path:
    return xdg_cache_home() / "hypr" / "wallpaper" / "current" / "wall.set"


def runtime_lock_dir() -> Path:
    # Mirrors core/common.bash:hypr_runtime_root_dir so this shares a lock
    # directory, not just a lock name, with bash state_set.
    return runtime_root() / "hypr"


def state_data_file(target_file: str) -> Path:
    if target_file not in STATE_TARGETS:
        raise ValueError(f"Unsupported state target '{target_file}'")
    return xdg_state_home() / "hypr" / target_file


def state_lock_file(target_file: str) -> Path:
    return runtime_lock_dir() / f"state-{target_file}.lock"


def resolve_hyprshell() -> Optional[str]:
    hyprshell = shutil.which("hyprshell")
    if hyprshell:
        return hyprshell
    candidate = Path.home() / ".local" / "bin" / "hyprshell"
    if candidate.exists():
        return str(candidate)
    return None


def positive_seconds(raw_value, default: float) -> float:
    try:
        seconds = float(raw_value)
        if seconds > 0:
            return seconds
    except Exception:
        pass
    return float(default)


def watchdog_interval_seconds(config: dict) -> float:
    default = DEFAULT_CONFIG["watchdog_interval_seconds"]
    return positive_seconds(config.get("watchdog_interval_seconds", default), default)


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


def load_state(state_file: Path = STATE_FILE) -> dict:
    defaults = {
        "current_mode": "dark",
        "last_change": None,
        "manual_override_until": None,
    }
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text())
            if isinstance(state, dict):
                state.pop("last_prewarm", None)
                state.pop("last_prewarm_pid", None)
                return {**defaults, **state}
        except Exception as exc:
            print(f"Warning: Failed to load state from {state_file}: {exc}", file=sys.stderr)
    return defaults


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, path)


@contextmanager
def held_state_lock(target_file: str):
    lock_file = state_lock_file(target_file)
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock_file, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def set_state_value(var_name: str, var_value: str, target_file: str = "staterc") -> None:
    state_file = state_data_file(target_file)

    if target_file == "color_variant":
        if not var_value:
            raise ValueError("color_variant value required")
        with held_state_lock(target_file):
            atomic_write_text(state_file, f"{var_value}\n")
        return

    if not var_name:
        raise ValueError("state variable name required")

    value_prefix = "export " if target_file == "env-overrides" else ""
    quoted_value = shell_quote_value(str(var_value))
    state_file.parent.mkdir(parents=True, exist_ok=True)

    with held_state_lock(target_file):
        existing_lines = state_file.read_text().splitlines() if state_file.exists() else []
        updated_lines = []
        for line in existing_lines:
            stripped = line.strip()
            if not stripped:
                updated_lines.append(line)
                continue
            normalized = stripped
            if normalized.startswith("export "):
                normalized = normalized[len("export ") :].lstrip()
            if normalized.startswith(f"{var_name}="):
                continue
            updated_lines.append(line)
        updated_lines.append(f"{value_prefix}{var_name}={quoted_value}")
        atomic_write_text(state_file, "\n".join(updated_lines) + "\n")


def save_state(state: dict, state_file: Path = STATE_FILE) -> None:
    atomic_write_text(state_file, json.dumps(state))


def read_staterc() -> dict:
    staterc = state_data_file("staterc")
    if not staterc.exists():
        return {}
    try:
        return load_shell_assignments(staterc)
    except Exception:
        return {}


def read_color_variant_file() -> Optional[str]:
    variant_file = state_data_file("color_variant")
    if variant_file.exists():
        return variant_file.read_text().strip()
    return None


def read_active_palette() -> dict:
    palette_file = active_palette_file()
    if not palette_file.exists():
        return {}
    try:
        data = json.loads(palette_file.read_text())
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def resolve_wallpaper(staterc_values: dict) -> Optional[Path]:
    cache_wall = wallpaper_state_file()
    if cache_wall.exists():
        return cache_wall.resolve()

    theme = staterc_values.get("HYPR_THEME")
    if theme:
        theme_wall = xdg_config_home() / "hypr" / "themes" / theme / "wall.set"
        if theme_wall.exists():
            return theme_wall.resolve()
    return None


def load_state_env(config_file: Path | None = None) -> dict:
    config_file = state_data_file("env-overrides") if config_file is None else config_file
    if not config_file.exists():
        return {}
    try:
        return load_shell_assignments(config_file)
    except Exception:
        return {}


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


def resolve_auto_location(config: dict) -> None:
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
        return sun_times["sunrise"].replace(tzinfo=None), sun_times["sunset"].replace(tzinfo=None)
    except Exception as exc:
        print(f"Warning: Failed to calculate sun times: {exc}")
        return None


def get_sun_times(config: dict, target_date: Optional[date] = None) -> tuple[datetime, datetime]:
    if target_date is None:
        target_date = datetime.now().date()
    sun_times = astral_sun_times(config, target_date) if ASTRAL_AVAILABLE else None
    sunrise, sunset = sun_times or (datetime.combine(target_date, FALLBACK_SUNRISE), datetime.combine(target_date, FALLBACK_SUNSET))
    inset = timedelta(minutes=config["daylight_inset_minutes"])
    return sunrise + inset, sunset - inset


def next_sun_boundary(config: dict, now: datetime) -> datetime:
    sunrise_today, sunset_today = get_sun_times(config, now.date())
    if now < sunrise_today:
        return sunrise_today
    if now < sunset_today:
        return sunset_today
    sunrise_tomorrow, _ = get_sun_times(config, (now + timedelta(days=1)).date())
    return sunrise_tomorrow


def manual_override_deadline(state: dict) -> Optional[datetime]:
    raw_until = state.get("manual_override_until")
    if not raw_until:
        return None
    try:
        return datetime.fromisoformat(raw_until)
    except Exception:
        state["manual_override_until"] = None
        return None
