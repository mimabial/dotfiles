#!/usr/bin/env python3
"""
Auto Theme Daemon - Sunrise/sunset scheduler

Automatically switches between light and dark themes based on:
1. Sunrise/sunset times

Configuration: ~/.config/hypr/auto_theme.conf
"""

import os
import sys
import json
import time
import signal
import ctypes
import select
import struct
import subprocess
import shutil
import threading
from pathlib import Path
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from typing import Optional, Literal

# Add hyprshell venv to path
VENV_PATH = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hypr/pip_env"
if VENV_PATH.exists():
    pyver = f"python{sys.version_info.major}.{sys.version_info.minor}"
    sys.path.insert(0, str(VENV_PATH / "lib" / pyver / "site-packages"))

try:
    from astral import LocationInfo
    from astral.sun import sun
    ASTRAL_AVAILABLE = True
except ImportError:
    ASTRAL_AVAILABLE = False
    print("Warning: astral not installed, sunrise/sunset calculation disabled")

# === Configuration ===

_xdg_config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
_xdg_state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
_xdg_cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
_tmpdir = Path(os.environ.get("TMPDIR", "/tmp"))

CONFIG_FILE = _xdg_config / "hypr/auto_theme.conf"
STATE_FILE = _xdg_state / "hypr/auto_theme_state.json"
NVIM_SETTINGS = _xdg_cache / "nvim/theme_settings.json"
STATE_LOCATION_ENV_KEYS = {
    "AUTO_THEME_LATITUDE": "latitude",
    "AUTO_THEME_LONGITUDE": "longitude",
    "AUTO_THEME_TIMEZONE": "timezone",
}

DEFAULT_CONFIG = {
    # Location for sunrise/sunset
    # Set to "auto" to detect via IP geolocation
    "latitude": "auto",
    "longitude": "auto",
    "timezone": "auto",

    # Timing
    "check_interval_seconds": 60,  # Watchdog fallback interval
    "sun_offset_minutes": 30,      # Minutes after sunrise / before sunset

    # What to control
    "control_hyprland": True,
    "control_nvim": True,

    # Manual override duration (minutes, 0 = disabled)
    "manual_override_duration": 120,
}


class InotifyPathWatcher:
    """Lightweight inotify file watcher using ctypes."""

    IN_ATTRIB = 0x00000004
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    IN_DELETE = 0x00000200
    EVENT_MASK = (
        IN_ATTRIB
        | IN_CLOSE_WRITE
        | IN_MOVED_FROM
        | IN_MOVED_TO
        | IN_CREATE
        | IN_DELETE
    )
    HEADER_SIZE = struct.calcsize("iIII")

    def __init__(self, on_change):
        self.on_change = on_change
        self.fd = None
        self.libc = None
        self._stop_event = threading.Event()
        self._thread = None
        self._lock = threading.Lock()
        self._targets_by_dir: dict[str, set[str]] = {}
        self._watches: dict[int, str] = {}

    def start(self, paths: list[Path]) -> bool:
        try:
            self.libc = ctypes.CDLL("libc.so.6", use_errno=True)
            self.libc.inotify_init.restype = ctypes.c_int
            self.libc.inotify_add_watch.argtypes = [
                ctypes.c_int,
                ctypes.c_char_p,
                ctypes.c_uint32,
            ]
            self.libc.inotify_add_watch.restype = ctypes.c_int
            self.libc.inotify_rm_watch.argtypes = [ctypes.c_int, ctypes.c_int]
            self.libc.inotify_rm_watch.restype = ctypes.c_int

            self.fd = self.libc.inotify_init()
            if self.fd < 0:
                self.fd = None
                return False
        except Exception:
            self.fd = None
            return False

        self._configure(paths)
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        return True

    def _configure(self, paths: list[Path]):
        targets: dict[str, set[str]] = {}
        for path in paths:
            parent = path.parent
            try:
                parent.mkdir(parents=True, exist_ok=True)
            except Exception:
                continue
            targets.setdefault(str(parent), set()).add(path.name)

        with self._lock:
            self._targets_by_dir = targets
            self._reset_watches_locked()

    def _reset_watches_locked(self):
        if self.fd is None or self.libc is None:
            return

        for wd in list(self._watches.keys()):
            try:
                self.libc.inotify_rm_watch(self.fd, wd)
            except Exception:
                pass
        self._watches.clear()

        for dir_path in sorted(self._targets_by_dir.keys()):
            try:
                wd = self.libc.inotify_add_watch(
                    self.fd,
                    dir_path.encode(),
                    self.EVENT_MASK,
                )
            except Exception:
                wd = -1
            if wd >= 0:
                self._watches[wd] = dir_path

    def _run(self):
        while not self._stop_event.is_set():
            if self.fd is None:
                break
            try:
                ready, _, _ = select.select([self.fd], [], [], 1.0)
            except Exception:
                break

            if not ready:
                continue

            try:
                data = os.read(self.fd, 4096)
            except Exception:
                continue

            i = 0
            while i + self.HEADER_SIZE <= len(data):
                wd, _mask, _cookie, name_len = struct.unpack_from("iIII", data, i)
                i += self.HEADER_SIZE
                raw_name = data[i : i + name_len]
                i += name_len
                if name_len <= 0:
                    continue

                name = raw_name.split(b"\0", 1)[0].decode("utf-8", errors="ignore")
                if not name:
                    continue

                with self._lock:
                    dir_path = self._watches.get(wd)
                    if not dir_path:
                        continue
                    if name not in self._targets_by_dir.get(dir_path, set()):
                        continue
                    changed_path = Path(dir_path) / name

                try:
                    self.on_change(changed_path)
                except Exception:
                    pass

    def stop(self):
        self._stop_event.set()
        if self.fd is not None:
            try:
                os.close(self.fd)
            except Exception:
                pass
            self.fd = None
        if self._thread is not None:
            self._thread.join(timeout=1.0)
        self._thread = None


class AutoTheme:
    def __init__(self):
        self.config = self._load_config()
        self._resolve_auto_location()
        self.state = self._load_state()
        self.running = True
        self.stop_event = threading.Event()
        self.wake_event = threading.Event()
        self._event_lock = threading.Lock()
        self._pending_toggle = False
        self._pending_refresh = False
        self._pending_config_reload = False
        self._pending_state_refresh = False
        self._watcher: Optional[InotifyPathWatcher] = None
        self._watchdog_due_at: Optional[datetime] = None

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGUSR1, self._handle_toggle)  # Manual toggle
        signal.signal(signal.SIGUSR2, self._handle_refresh)  # Force refresh

    def _state_home(self) -> Path:
        return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))

    def _config_home(self) -> Path:
        return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))

    def _cache_home(self) -> Path:
        return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))

    def _color_state_file(self) -> Path:
        return self._cache_home() / "hypr" / "color.gen.state"

    def _wallpaper_state_file(self) -> Path:
        return self._cache_home() / "hypr" / "wallpaper" / "current" / "wall.set"

    def _state_config_file(self) -> Path:
        return self._state_home() / "hypr" / "env-overrides"

    def _theme_update_lock_file(self) -> Path:
        runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
        return runtime_dir / "theme-update.lock"

    def _positive_seconds(self, raw_value, default: float) -> float:
        try:
            seconds = float(raw_value)
            if seconds > 0:
                return seconds
        except Exception:
            pass
        return float(default)

    def _watchdog_interval_seconds(self) -> float:
        return self._positive_seconds(self.config.get("check_interval_seconds", 60), 60)

    def _watched_paths(self) -> list[Path]:
        return [
            CONFIG_FILE,
            self._state_config_file(),
            self._state_home() / "hypr" / "staterc",
            self._state_home() / "hypr" / "color_variant",
            self._color_state_file(),
        ]

    def _on_watched_file_changed(self, changed_path: Path):
        with self._event_lock:
            if changed_path == CONFIG_FILE or changed_path == self._state_config_file():
                self._pending_config_reload = True
            else:
                self._pending_state_refresh = True
        self.wake_event.set()

    def _start_file_watcher(self):
        watch_paths = self._watched_paths()
        watcher = InotifyPathWatcher(self._on_watched_file_changed)
        if watcher.start(watch_paths):
            self._watcher = watcher
            return
        print("Warning: inotify watcher unavailable, relying on signals and timed fallbacks")
        self._watcher = None

    def _stop_file_watcher(self):
        if self._watcher is not None:
            self._watcher.stop()
            self._watcher = None

    def _consume_pending_events(self) -> dict:
        with self._event_lock:
            pending = {
                "toggle": self._pending_toggle,
                "refresh": self._pending_refresh,
                "config_reload": self._pending_config_reload,
                "state_refresh": self._pending_state_refresh,
            }
            self._pending_toggle = False
            self._pending_refresh = False
            self._pending_config_reload = False
            self._pending_state_refresh = False
        return pending

    def _reload_config(self):
        self.config = self._load_config()
        self._resolve_auto_location()

    def _read_staterc(self) -> dict:
        staterc = self._state_home() / "hypr" / "staterc"
        if not staterc.exists():
            return {}
        values = {}
        for line in staterc.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"')
        return values

    def _read_color_variant_file(self) -> Optional[str]:
        color_variant_file = self._state_home() / "hypr" / "color_variant"
        if color_variant_file.exists():
            return color_variant_file.read_text().strip()
        return None

    def _read_color_state(self) -> dict:
        state_file = self._color_state_file()
        if not state_file.exists():
            return {}
        data = {}
        try:
            for line in state_file.read_text().splitlines():
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                data[key.strip()] = value.strip()
        except Exception:
            return {}
        return data

    def _pywal_state_matches(self, mode: Literal["light", "dark"], staterc_values: dict) -> bool:
        state = self._read_color_state()
        if not state:
            return False
        selected_color_mode_raw = state.get("selected_color_mode")
        try:
            selected_color_mode = int(selected_color_mode_raw) if selected_color_mode_raw is not None else None
        except ValueError:
            selected_color_mode = None
        if selected_color_mode != 1:
            return False
        if state.get("color_variant") != mode:
            return False
        wallpaper = self._resolve_wallpaper(staterc_values)
        if wallpaper and state.get("wallpaper") and str(wallpaper) != state.get("wallpaper"):
            return False
        return True

    def _read_theme_from_wal_conf(self) -> Optional[str]:
        wal_conf = self._config_home() / "hypr" / "themes" / "wal.conf"
        if not wal_conf.exists():
            return None
        for line in wal_conf.read_text().splitlines():
            line = line.strip()
            if line.startswith("$HYPR_THEME="):
                return line.split("=", 1)[1].strip().strip('"')
        return None

    def _resolve_wallpaper(self, staterc_values: dict) -> Optional[Path]:
        cache_wall = self._cache_home() / "hypr" / "wallpaper" / "current" / "wall.set"
        if cache_wall.exists():
            return cache_wall.resolve()

        theme = staterc_values.get("HYPR_THEME") or self._read_theme_from_wal_conf()
        if theme:
            theme_wall = self._config_home() / "hypr" / "themes" / theme / "wall.set"
            if theme_wall.exists():
                return theme_wall.resolve()
        return None

    def _resolve_hyprshell(self) -> Optional[str]:
        hyprshell = shutil.which("hyprshell")
        if hyprshell:
            return hyprshell
        candidate = Path.home() / ".local" / "bin" / "hyprshell"
        if candidate.exists():
            return str(candidate)
        return None

    def _load_state_env(self) -> dict:
        values = {}
        config_file = self._state_config_file()
        if not config_file.exists():
            return values

        try:
            for raw_line in config_file.read_text().splitlines():
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                if line.startswith("export "):
                    line = line[len("export ") :].lstrip()
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
        except Exception:
            return {}

        return values

    def _apply_location_overrides_from_state(self):
        state_env = self._load_state_env()
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
                self.config[config_key] = "auto"
                continue

            if config_key in ("latitude", "longitude"):
                try:
                    self.config[config_key] = float(value)
                except ValueError:
                    print(f"Warning: Invalid {env_key} value '{value}', ignoring")
                continue

            self.config[config_key] = value

    def _resolve_auto_location(self):
        """Resolve 'auto' location via IP geolocation."""
        self._apply_location_overrides_from_state()

        if (self.config.get("latitude") == "auto" or
            self.config.get("longitude") == "auto" or
            self.config.get("timezone") == "auto"):

            try:
                import urllib.request
                import json as json_mod

                # Use ipinfo over HTTPS for geolocation
                with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as resp:
                    data = json_mod.loads(resp.read().decode())
                if data.get("error"):
                    raise ValueError(f"Geolocation failed: {data.get('error')}")

                loc_raw = str(data.get("loc", "")).strip()
                lat = lon = None
                if "," in loc_raw:
                    lat_raw, lon_raw = loc_raw.split(",", 1)
                    lat = float(lat_raw.strip())
                    lon = float(lon_raw.strip())

                if self.config.get("latitude") == "auto":
                    if lat is None:
                        raise ValueError("Geolocation response missing latitude")
                    self.config["latitude"] = lat
                if self.config.get("longitude") == "auto":
                    if lon is None:
                        raise ValueError("Geolocation response missing longitude")
                    self.config["longitude"] = lon
                if self.config.get("timezone") == "auto":
                    self.config["timezone"] = data.get("timezone", "UTC") or "UTC"

                print(f"Auto-detected location: {data.get('city', 'Unknown')}, {data.get('country', 'Unknown')}")
                print(f"  Coordinates: {self.config['latitude']}, {self.config['longitude']}")
                print(f"  Timezone: {self.config['timezone']}")

            except Exception as e:
                print(f"Warning: Failed to auto-detect location: {e}")
                print("Using fallback location (UTC, equator)")
                if self.config.get("latitude") == "auto":
                    self.config["latitude"] = 0
                if self.config.get("longitude") == "auto":
                    self.config["longitude"] = 0
                if self.config.get("timezone") == "auto":
                    self.config["timezone"] = "UTC"

    def _load_config(self) -> dict:
        """Load configuration from file or use defaults."""
        config = DEFAULT_CONFIG.copy()

        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    # Support both JSON and simple key=value format
                    content = f.read().strip()
                    if content.startswith('{'):
                        user_config = json.loads(content)
                    else:
                        user_config = {}
                        for line in content.split('\n'):
                            line = line.strip()
                            if line and not line.startswith('#') and '=' in line:
                                key, value = line.split('=', 1)
                                key = key.strip()
                                value = value.strip()
                                # Parse value type
                                if value.lower() in ('true', 'false'):
                                    value = value.lower() == 'true'
                                elif value.replace('.', '').replace('-', '').isdigit():
                                    value = float(value) if '.' in value else int(value)
                                user_config[key] = value
                    config.update(user_config)
            except Exception as e:
                print(f"Warning: Failed to load config: {e}")

        return config

    def _load_state(self) -> dict:
        """Load persisted state."""
        defaults = {
            "current_mode": "dark",
            "last_change": None,
            "manual_override_until": None,
        }
        if STATE_FILE.exists():
            try:
                with open(STATE_FILE) as f:
                    state = json.load(f)
                if isinstance(state, dict):
                    state.pop("last_prewarm", None)
                    state.pop("last_prewarm_pid", None)
                    return {**defaults, **state}
            except:
                pass
        return defaults

    def _save_state(self):
        """Persist state to file."""
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(STATE_FILE, 'w') as f:
            json.dump(self.state, f)

    def _get_sun_times(self, target_date: Optional[date] = None) -> tuple[datetime, datetime]:
        """Get sunrise and sunset times for a given date."""
        if target_date is None:
            target_date = datetime.now().date()

        if not ASTRAL_AVAILABLE:
            # Fallback: 6 AM and 6 PM
            base = datetime.combine(target_date, datetime.min.time())
            sunrise = base.replace(hour=6, minute=0, second=0, microsecond=0)
            sunset = base.replace(hour=18, minute=0, second=0, microsecond=0)
            return sunrise, sunset

        try:
            location = LocationInfo(
                latitude=self.config["latitude"],
                longitude=self.config["longitude"],
                timezone=self.config["timezone"],
            )
            tz_name = str(self.config.get("timezone", "UTC") or "UTC")
            try:
                tz = ZoneInfo(tz_name)
            except Exception:
                tz = ZoneInfo("UTC")
            s = sun(location.observer, date=target_date, tzinfo=tz)

            # Convert to local naive datetime
            sunrise = s["sunrise"].replace(tzinfo=None)
            sunset = s["sunset"].replace(tzinfo=None)

            # Apply offset
            offset = timedelta(minutes=self.config["sun_offset_minutes"])
            sunrise += offset
            sunset -= offset

            return sunrise, sunset
        except Exception as e:
            print(f"Warning: Failed to calculate sun times: {e}")
            now = datetime.combine(target_date, datetime.min.time())
            return (
                now.replace(hour=6, minute=30),
                now.replace(hour=17, minute=30)
            )

    def _next_sun_boundary(self, now: datetime) -> datetime:
        sunrise_today, sunset_today = self._get_sun_times(now.date())
        if now < sunrise_today:
            return sunrise_today
        if now < sunset_today:
            return sunset_today
        sunrise_tomorrow, _ = self._get_sun_times((now + timedelta(days=1)).date())
        return sunrise_tomorrow

    def _manual_override_deadline(self) -> Optional[datetime]:
        raw_until = self.state.get("manual_override_until")
        if not raw_until:
            return None
        try:
            return datetime.fromisoformat(raw_until)
        except Exception:
            self.state["manual_override_until"] = None
            return None

    def _should_be_light(self) -> tuple[bool, str]:
        """
        Determine if we should be in light mode.
        Returns (should_be_light, reason).
        """
        now = datetime.now()

        # Check manual override
        override_until = self._manual_override_deadline()
        if override_until is not None:
            if now < override_until:
                is_light = self.state["current_mode"] == "light"
                return is_light, "manual_override"
            self.state["manual_override_until"] = None

        # Use sunrise/sunset schedule
        sunrise, sunset = self._get_sun_times(now.date())
        is_daytime = sunrise <= now <= sunset
        reason = f"sun ({'day' if is_daytime else 'night'}, rise={sunrise.strftime('%H:%M')}, set={sunset.strftime('%H:%M')})"

        return is_daytime, reason

    def _is_auto_mode(self) -> bool:
        """Check if selected_color_mode is 1 (auto/wallpaper)."""
        staterc_values = self._read_staterc()
        raw = staterc_values.get("selected_color_mode")
        try:
            return int(raw) == 1 if raw is not None else False
        except ValueError:
            return False

    def _apply_mode(self, mode: Literal["light", "dark"], reason: str):
        """Apply the theme mode to all configured targets."""
        if mode == self.state["current_mode"]:
            if self._is_auto_mode():
                if self.config["control_nvim"]:
                    self._reconcile_nvim(mode)
                if self.config["control_hyprland"]:
                    current_color_variant = self._read_color_variant_file()
                    staterc_values = self._read_staterc()
                    if current_color_variant != mode or not self._pywal_state_matches(mode, staterc_values):
                        if self._theme_update_lock_file().exists():
                            return
                        self._apply_hyprland(mode)
            return  # No change needed

        print(f"[{datetime.now().strftime('%H:%M:%S')}] Switching to {mode} mode ({reason})")

        # Always update state (used by Neovim AUTO_DETECT mode via state file)
        self.state["current_mode"] = mode
        self.state["last_change"] = datetime.now().isoformat()
        self._save_state()

        # Only apply to targets when in auto/wallpaper mode
        if not self._is_auto_mode():
            print(f"Auto mode inactive, skipping target updates")
            return

        if self.config["control_nvim"]:
            self._apply_nvim(mode)

        if self.config["control_hyprland"]:
            self._apply_hyprland(mode)

    def _reconcile_nvim(self, mode: Literal["light", "dark"]):
        """Re-apply Neovim settings if they don't match the desired mode."""
        try:
            if NVIM_SETTINGS.exists():
                with open(NVIM_SETTINGS) as f:
                    settings = json.load(f)
                if settings.get("background") == mode:
                    return  # Already in sync
        except Exception:
            pass
        self._apply_nvim(mode)

    def _apply_nvim(self, mode: Literal["light", "dark"]):
        """Update Neovim theme settings file.

        Neovim instances with file watchers will automatically pick up the change.
        No need to send remote commands - the file change triggers sync.
        """
        try:
            if NVIM_SETTINGS.exists():
                with open(NVIM_SETTINGS) as f:
                    settings = json.load(f)
            else:
                settings = {}

            settings["background"] = mode

            NVIM_SETTINGS.parent.mkdir(parents=True, exist_ok=True)
            with open(NVIM_SETTINGS, 'w') as f:
                json.dump(settings, f)

            # Neovim file watchers will detect this change automatically

        except Exception as e:
            print(f"Warning: Failed to update Neovim: {e}")

    def _apply_hyprland(self, mode: Literal["light", "dark"]):
        """Update Hyprland/system theme. Caller must verify auto mode is active."""
        try:
            state_home = self._state_home()
            staterc = state_home / "hypr" / "staterc"
            staterc.parent.mkdir(parents=True, exist_ok=True)

            staterc_values = self._read_staterc()
            lines = staterc.read_text().splitlines() if staterc.exists() else []

            updated = False
            for i, line in enumerate(lines):
                if line.startswith("BACKGROUND_MODE="):
                    lines[i] = f'BACKGROUND_MODE="{mode}"'
                    updated = True
                    break
            if not updated:
                lines.append(f'BACKGROUND_MODE="{mode}"')

            staterc.write_text("\n".join(lines) + "\n")

            color_variant_file = state_home / "hypr" / "color_variant"
            color_variant_file.parent.mkdir(parents=True, exist_ok=True)
            current_color_variant = color_variant_file.read_text().strip() if color_variant_file.exists() else ""
            if current_color_variant != mode:
                color_variant_file.write_text(f"{mode}\n")

            wallpaper = self._resolve_wallpaper(staterc_values)
            if not wallpaper or not wallpaper.exists():
                print("Warning: Could not resolve current wallpaper for pywal update")
                return

            hyprshell = self._resolve_hyprshell()
            if not hyprshell:
                print("Warning: hyprshell not found, cannot apply pywal colors")
                return

            env = os.environ.copy()
            env_path = env.get("PATH", "")
            env["PATH"] = f"{Path.home() / '.local' / 'bin'}:{env_path}"
            result = subprocess.run(
                [hyprshell, "color.set", str(wallpaper)],
                env=env,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "").strip()
                print(f"Warning: Failed to apply pywal colors: {detail or 'unknown error'}")

        except Exception as e:
            print(f"Warning: Failed to update Hyprland: {e}")

    def _handle_signal(self, signum, frame):
        """Handle termination signals."""
        print(f"\nReceived signal {signum}, shutting down...")
        self.running = False
        self.stop_event.set()
        self.wake_event.set()

    def _handle_toggle(self, signum, frame):
        """Handle manual toggle (SIGUSR1)."""
        with self._event_lock:
            self._pending_toggle = True
        self.wake_event.set()

    def _handle_refresh(self, signum, frame):
        """Handle force refresh (SIGUSR2)."""
        with self._event_lock:
            self._pending_refresh = True
        self.wake_event.set()

    def _apply_toggle(self):
        new_mode = "dark" if self.state["current_mode"] == "light" else "light"

        # Set override duration
        if self.config["manual_override_duration"] > 0:
            override_until = datetime.now() + timedelta(minutes=self.config["manual_override_duration"])
            self.state["manual_override_until"] = override_until.isoformat()
            print(f"Manual override until {override_until.strftime('%H:%M')}")

        self._apply_mode(new_mode, "manual_toggle")

    def _apply_refresh(self):
        print("Force refresh requested")
        self.state["manual_override_until"] = None  # Clear override
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", reason)

    def run(self):
        """Main daemon loop (event-driven with timed fallbacks)."""
        print(f"Auto-theme daemon started (PID: {os.getpid()})")
        print(f"  Location: {self.config['latitude']}, {self.config['longitude']}")
        print(f"  Watchdog interval: {self._watchdog_interval_seconds():g}s")

        self._start_file_watcher()

        # Initial check
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", reason)
        now = datetime.now()
        self._watchdog_due_at = now + timedelta(seconds=self._watchdog_interval_seconds())

        try:
            while self.running:
                try:
                    now = datetime.now()
                    sun_due_at = self._next_sun_boundary(now)
                    override_due_at = self._manual_override_deadline()

                    deadlines = []
                    if self._watchdog_due_at is not None:
                        deadlines.append(self._watchdog_due_at)
                    if sun_due_at is not None:
                        deadlines.append(sun_due_at)
                    if override_due_at is not None:
                        deadlines.append(override_due_at)

                    timeout = None
                    if deadlines:
                        timeout = max(
                            0.0,
                            min((deadline - now).total_seconds() for deadline in deadlines),
                        )

                    self.wake_event.wait(timeout)
                    self.wake_event.clear()
                    if not self.running:
                        break

                    now = datetime.now()
                    events = self._consume_pending_events()

                    if events["config_reload"]:
                        print("Auto-theme config changed, reloading")
                        self._reload_config()
                        self._watchdog_due_at = now + timedelta(seconds=self._watchdog_interval_seconds())

                    if events["toggle"]:
                        self._apply_toggle()
                        now = datetime.now()
                        self._watchdog_due_at = now + timedelta(seconds=self._watchdog_interval_seconds())
                        continue

                    if events["refresh"]:
                        self._apply_refresh()
                        now = datetime.now()
                        self._watchdog_due_at = now + timedelta(seconds=self._watchdog_interval_seconds())
                        continue

                    trigger_reasons = []
                    if events["config_reload"]:
                        trigger_reasons.append("config_change")
                    if events["state_refresh"]:
                        trigger_reasons.append("state_change")

                    if self._watchdog_due_at is not None and now >= self._watchdog_due_at:
                        trigger_reasons.append("watchdog")
                        self._watchdog_due_at = now + timedelta(seconds=self._watchdog_interval_seconds())

                    if sun_due_at is not None and now >= sun_due_at:
                        trigger_reasons.append("sun_boundary")

                    if override_due_at is not None and now >= override_due_at:
                        trigger_reasons.append("override_expiry")

                    if trigger_reasons:
                        should_be_light, reason = self._should_be_light()
                        unique_reasons = ",".join(dict.fromkeys(trigger_reasons))
                        mode = "light" if should_be_light else "dark"
                        self._apply_mode(mode, f"{reason}; trigger={unique_reasons}")

                except Exception as e:
                    print(f"Error in main loop: {e}")
                    time.sleep(5)
        finally:
            self._stop_file_watcher()

        print("Auto-theme daemon stopped")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Auto theme daemon")
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    parser.add_argument("--status", action="store_true", help="Show current status")
    parser.add_argument("--toggle", action="store_true", help="Send toggle signal to running daemon")
    parser.add_argument("--refresh", action="store_true", help="Send refresh signal to running daemon")
    args = parser.parse_args()

    if args.status:
        if STATE_FILE.exists():
            state = json.loads(STATE_FILE.read_text())
            print(f"Current mode: {state.get('current_mode', 'unknown')}")
            print(f"Last change: {state.get('last_change', 'never')}")
            if state.get('manual_override_until'):
                print(f"Manual override until: {state['manual_override_until']}")
        else:
            print("No state file found")

        # Show sun times
        if ASTRAL_AVAILABLE:
            daemon = AutoTheme()
            sunrise, sunset = daemon._get_sun_times()
            print(f"Sunrise: {sunrise.strftime('%H:%M')}")
            print(f"Sunset: {sunset.strftime('%H:%M')}")
        return

    if args.toggle or args.refresh:
        # Find running daemon and send signal
        import glob
        for pidfile in glob.glob(str(_tmpdir / "auto_theme_*.pid")):
            try:
                pid = int(Path(pidfile).read_text().strip())
                os.kill(pid, signal.SIGUSR1 if args.toggle else signal.SIGUSR2)
                print(f"Signal sent to PID {pid}")
                return
            except:
                continue
        print("No running daemon found")
        return

    daemon = AutoTheme()

    if args.once:
        should_be_light, reason = daemon._should_be_light()
        daemon._apply_mode("light" if should_be_light else "dark", reason)
    else:
        # Write PID file
        pidfile = _tmpdir / f"auto_theme_{os.getpid()}.pid"
        pidfile.write_text(str(os.getpid()))
        try:
            daemon.run()
        finally:
            pidfile.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
