#!/usr/bin/env python3
import argparse
import errno
import fcntl
import json
import os
import select
import shutil
import signal
import struct
import subprocess
import sys
import time
from collections import deque
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Literal, NamedTuple, Optional

HYPR_LIB_DIR = Path(__file__).resolve().parents[1]
if str(HYPR_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(HYPR_LIB_DIR))

from auto_theme_schedule import (
    ASTRAL_AVAILABLE,
    CONFIG_FILE,
    daylight_window,
    load_config,
    next_daylight_boundary,
    resolve_location_settings_into,
)
from auto_theme_state import (
    STATE_FILE,
    TMPDIR_PATH,
    active_palette_file,
    load_state,
    manual_override_deadline,
    read_active_palette,
    read_color_variant_file,
    read_staterc,
    resolve_wallpaper,
    save_state,
    set_state_value,
    state_data_file,
    wallpaper_state_file,
)
from auto_theme_watch import InotifyPathWatcher
from pyutils.lock_paths import runtime_lock_path_ensure_parent
from pyutils import child_process

PAIR_LOOKUP_TIMEOUT_SECONDS = 10
LOCALTIME_FILE = Path("/etc/localtime")

AUTO_COLOR_MODE = 1
LEGACY_THEME_COLOR_MODE = "0"


def file_identity(path: Path) -> Optional[tuple[int, int, int]]:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    return info.st_ino, info.st_mtime_ns, info.st_size


class PendingThemeEvents(NamedTuple):
    signals: list[str]
    config_reload: bool
    state_refresh: bool
    clock_change: bool


class WakeupPipe:
    def __init__(self):
        self.read_fd, self.write_fd = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)

    def set(self):
        try:
            os.write(self.write_fd, b"\0")
        except BlockingIOError:
            pass

    def clear(self):
        while True:
            try:
                os.read(self.read_fd, 4096)
            except BlockingIOError:
                return

    def close(self):
        os.close(self.read_fd)
        os.close(self.write_fd)


class WallClockTimer:
    EXPIRATION_COUNT_SIZE = struct.calcsize("Q")

    def __init__(self):
        self.fd = os.timerfd_create(time.CLOCK_REALTIME, flags=os.TFD_NONBLOCK | os.TFD_CLOEXEC)

    def arm(self, deadline: datetime):
        os.timerfd_settime(self.fd, flags=os.TFD_TIMER_ABSTIME | os.TFD_TIMER_CANCEL_ON_SET, initial=deadline.timestamp())

    def consume_clock_change(self) -> bool:
        try:
            os.read(self.fd, self.EXPIRATION_COUNT_SIZE)
        except BlockingIOError:
            return False
        except OSError as exc:
            if exc.errno == errno.ECANCELED:
                return True
            raise
        return False

    def close(self):
        os.close(self.fd)


class AutoThemeDaemon:
    def __init__(self):
        self.config = load_config()
        resolve_location_settings_into(self.config)
        self.state = load_state()
        self.running = True
        self.wake_event = WakeupPipe()
        self.deadline_timer = WallClockTimer()
        self._signal_events = deque()
        self._pending_config_reload = False
        self._pending_state_refresh = False
        self._pending_clock_change = False
        self._watcher: Optional[InotifyPathWatcher] = None
        self._sun_due_at: Optional[datetime] = None
        self._override_due_at: Optional[datetime] = None
        self._failed_apply_signature: Optional[tuple] = None

        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGUSR1, self._handle_toggle)
        signal.signal(signal.SIGUSR2, self._handle_refresh)

    def _active_palette_file(self) -> Path:
        return active_palette_file()

    def _state_config_file(self) -> Path:
        return state_data_file("env-overrides")

    def _theme_update_lock_file(self) -> Path:
        return runtime_lock_path_ensure_parent("theme_update")

    @contextmanager
    def _theme_update_lock(self):
        lock_file = self._theme_update_lock_file()
        lock_file.parent.mkdir(parents=True, exist_ok=True)
        with lock_file.open("a+") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    def _watched_state_paths(self) -> list[Path]:
        return [
            state_data_file("staterc"),
            state_data_file("color_variant"),
            wallpaper_state_file(),
            self._active_palette_file(),
        ]

    def _watched_paths(self) -> list[Path]:
        return [CONFIG_FILE, self._state_config_file(), *self._watched_state_paths(), LOCALTIME_FILE]

    def _state_files_signature(self) -> tuple:
        return tuple(file_identity(path) for path in self._watched_state_paths())

    def _on_watched_file_changed(self, changed_path: Path):
        if changed_path == LOCALTIME_FILE:
            time.tzset()
            self._pending_clock_change = True
        elif changed_path == CONFIG_FILE or changed_path == self._state_config_file():
            self._pending_config_reload = True
        else:
            self._pending_state_refresh = True

    def _start_file_watcher(self):
        watcher = InotifyPathWatcher()
        if watcher.start(self._watched_paths()):
            self._watcher = watcher
            return
        print("Warning: inotify watcher unavailable, relying on signals and the daylight timer")
        self._watcher = None

    def _stop_file_watcher(self):
        if self._watcher is not None:
            self._watcher.close()
            self._watcher = None

    def _wait_for_events(self, include_deadline: bool):
        sources = [self.wake_event.read_fd]
        if self._watcher is not None:
            sources.append(self._watcher.fd)
        if include_deadline:
            sources.append(self.deadline_timer.fd)
        select.select(sources, [], [])

    def _collect_events(self):
        self.wake_event.clear()
        if self._watcher is not None:
            for changed_path in self._watcher.read_changed_paths():
                self._on_watched_file_changed(changed_path)
        if self.deadline_timer.consume_clock_change():
            self._pending_clock_change = True

    def _consume_pending_events(self) -> PendingThemeEvents:
        signals = []
        while self._signal_events:
            signals.append(self._signal_events.popleft())
        pending = PendingThemeEvents(signals, self._pending_config_reload, self._pending_state_refresh, self._pending_clock_change)
        self._pending_config_reload = False
        self._pending_state_refresh = False
        self._pending_clock_change = False
        return pending

    def _reload_config(self):
        self.config = load_config()
        resolve_location_settings_into(self.config)

    @staticmethod
    def _color_source(staterc_values: dict) -> Literal["theme", "wallpaper"]:
        source = staterc_values.get("selected_color_source")
        if source in ("theme", "wallpaper"):
            return source
        return "theme" if staterc_values.get("selected_color_mode") in (None, LEGACY_THEME_COLOR_MODE) else "wallpaper"

    def _active_palette_matches(self, mode: Literal["light", "dark"], staterc_values: dict) -> bool:
        palette = read_active_palette()
        if not palette:
            return False
        if palette.get("background") != mode:
            return False

        if self._color_source(staterc_values) == "theme":
            theme = staterc_values.get("HYPR_THEME")
            return bool(
                theme
                and palette.get("mode") == "theme"
                and palette.get("source") == f"theme:{theme}"
            )

        if palette.get("mode") != "wallpaper":
            return False
        wallpaper = resolve_wallpaper(staterc_values)
        if wallpaper and palette.get("source") != f"wallpaper:{wallpaper.resolve()}":
            return False
        return True

    def _should_be_light(self) -> tuple[bool, str]:
        now = datetime.now()
        override_until = manual_override_deadline(self.state)
        if override_until is not None:
            if now < override_until:
                is_light = self.state["current_mode"] == "light"
                return is_light, "manual_override"
            self.state["manual_override_until"] = None

        daylight = daylight_window(self.config, now.date())
        is_daytime = daylight.starts_at <= now <= daylight.ends_at
        reason = f"daylight ({'day' if is_daytime else 'night'}, start={daylight.starts_at.strftime('%H:%M')}, end={daylight.ends_at.strftime('%H:%M')})"
        return is_daytime, reason

    def _is_auto_mode(self) -> bool:
        raw = read_staterc().get("selected_color_mode")
        try:
            return int(raw) == AUTO_COLOR_MODE if raw is not None else False
        except ValueError:
            return False

    def _apply_mode(self, mode: Literal["light", "dark"], reason: str) -> bool:
        if mode == self.state["current_mode"]:
            if self._is_auto_mode() and self.config["control_hyprland"]:
                current_color_variant = read_color_variant_file()
                staterc_values = read_staterc()
                if current_color_variant != mode or not self._active_palette_matches(mode, staterc_values):
                    return self._apply_desktop_palette(mode)
            return True

        print(f"[{datetime.now().strftime('%H:%M:%S')}] Switching to {mode} mode ({reason})")
        if not self._is_auto_mode():
            print("Auto mode inactive, skipping target updates")
        elif self.config["control_hyprland"] and not self._apply_desktop_palette(mode):
            print(f"Switch to {mode} mode failed; {self.state['current_mode']} mode stays recorded")
            return False

        self.state["current_mode"] = mode
        self.state["last_change"] = datetime.now().isoformat()
        save_state(self.state)
        return True

    def _pair_theme_for(self, current_theme: Optional[str], mode: str) -> Optional[str]:
        if not current_theme:
            return current_theme
        try:
            result = child_process.run(
                [str(HYPR_LIB_DIR / "theme/pairs.sh"), "--pair-for", current_theme, mode],
                capture_output=True,
                text=True,
                timeout=PAIR_LOOKUP_TIMEOUT_SECONDS,
            )
            target = result.stdout.strip()
            if result.returncode == 0 and target:
                return target
        except Exception as exc:
            print(f"Warning: pair resolution failed: {exc}")
        return current_theme

    def _switch_theme(self, theme: str) -> bool:
        try:
            result = subprocess.run(
                [str(HYPR_LIB_DIR / "theme/theme.switch.sh"), "-s", theme, "--quiet", "--from-auto"],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "").strip()
                print(f"Warning: theme switch to '{theme}' failed: {detail or 'unknown error'}")
                return False
            return True
        except Exception as exc:
            print(f"Warning: theme switch failed: {exc}")
            return False

    def _apply_desktop_palette(self, mode: Literal["light", "dark"]) -> bool:
        applied = self._attempt_desktop_palette(mode)
        self._failed_apply_signature = None if applied else self._state_files_signature()
        return applied

    def _attempt_desktop_palette(self, mode: Literal["light", "dark"]) -> bool:
        try:
            while True:
                staterc_values = read_staterc()
                color_source = self._color_source(staterc_values)
                current_theme = staterc_values.get("HYPR_THEME")
                target_theme = self._pair_theme_for(current_theme, mode) if color_source == "theme" else None
                if target_theme and current_theme and target_theme != current_theme:
                    return self._switch_theme(target_theme)
                with self._theme_update_lock():
                    current = read_staterc()
                    if current.get("HYPR_THEME") != current_theme or self._color_source(current) != color_source:
                        continue
                    return self._apply_palette(mode, current, color_source, current_theme)
        except Exception as exc:
            print(f"Warning: Failed to update desktop palette: {exc}")
            return False

    def _apply_palette(self, mode, staterc_values, color_source, current_theme) -> bool:
        env = os.environ.copy()
        env["PATH"] = f"{Path.home() / '.local' / 'bin'}:{env.get('PATH', '')}"
        hypr_theme = shutil.which("hypr-theme", path=env["PATH"])
        if not hypr_theme:
            print("Warning: hypr-theme not found, cannot apply colors")
            return False

        if current_theme:
            env["HYPR_THEME"] = current_theme

        if color_source == "theme":
            if not current_theme:
                print("Warning: Could not resolve current theme for palette update")
                return False
            command = [hypr_theme, "apply", current_theme]
        else:
            wallpaper = resolve_wallpaper(staterc_values)
            if not wallpaper or not wallpaper.exists():
                print("Warning: Could not resolve current wallpaper for palette update")
                return False
            command = [hypr_theme, "wallpaper", "--variant", mode, str(wallpaper)]

        result = subprocess.run(command, env=env, capture_output=True, text=True)
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            print(f"Warning: Failed to apply hypr-theme colors: {detail or 'unknown error'}")
            return False
        set_state_value("BACKGROUND_MODE", mode, "staterc")
        set_state_value("", mode, "color_variant")
        return True

    def _handle_signal(self, signum, frame):
        self.running = False

    def _handle_toggle(self, signum, frame):
        self._signal_events.append("toggle")

    def _handle_refresh(self, signum, frame):
        self._signal_events.append("refresh")

    def _apply_toggle(self):
        new_mode = "dark" if self.state["current_mode"] == "light" else "light"
        if not self._apply_mode(new_mode, "manual_toggle") or self.config["manual_override_minutes"] <= 0:
            return
        override_until = datetime.now() + timedelta(minutes=self.config["manual_override_minutes"])
        self.state["manual_override_until"] = override_until.isoformat()
        save_state(self.state)
        print(f"Manual override until {override_until.strftime('%H:%M')}")

    def _apply_refresh(self):
        print("Force refresh requested")
        self.state["manual_override_until"] = None
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", reason)

    def _apply_computed_mode(self, trigger=""):
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", f"{reason}; trigger={trigger}" if trigger else reason)

    def _arm_next_deadline(self):
        now = datetime.now()
        sun_due_at = next_daylight_boundary(self.config, now)
        override_due_at = manual_override_deadline(self.state)
        if override_due_at is not None and override_due_at <= now:
            override_due_at = None
        self.deadline_timer.arm(min(due for due in (sun_due_at, override_due_at) if due is not None))
        self._sun_due_at, self._override_due_at = sun_due_at, override_due_at

    def _trigger_reasons(self, events, now):
        reasons = []
        if events.config_reload:
            reasons.append("config_change")
        if events.state_refresh:
            reasons.append("state_change")
        if events.clock_change:
            reasons.append("clock_change")
        if self._sun_due_at is not None and now >= self._sun_due_at:
            reasons.append("sun_boundary")
        if self._override_due_at is not None and now >= self._override_due_at:
            reasons.append("override_expiry")
        return reasons

    def _handle_wake(self):
        now = datetime.now()
        events = self._consume_pending_events()

        if events.config_reload:
            print("Auto-theme config changed, reloading")
            self._reload_config()

        if events.signals:
            for event in events.signals:
                if event == "toggle":
                    self._apply_toggle()
                else:
                    self._apply_refresh()
            return

        trigger_reasons = self._trigger_reasons(events, now)
        if trigger_reasons == ["state_change"] and self._failed_apply_signature == self._state_files_signature():
            return
        if trigger_reasons:
            self._apply_computed_mode(",".join(dict.fromkeys(trigger_reasons)))

    def run(self):
        print(f"Auto-theme daemon started (PID: {os.getpid()})")
        print(f"  Location: {self.config['latitude']}, {self.config['longitude']}")

        signal.set_wakeup_fd(self.wake_event.write_fd)
        if self._signal_events:
            self.wake_event.set()
        self._start_file_watcher()
        self._apply_computed_mode()

        try:
            while self.running:
                try:
                    self._arm_next_deadline()
                    deadline_armed = True
                except Exception as exc:
                    print(f"Error scheduling the next daylight boundary: {exc}; waiting for the next signal or file change")
                    self._sun_due_at = self._override_due_at = None
                    deadline_armed = False
                self._wait_for_events(include_deadline=deadline_armed)
                try:
                    self._collect_events()
                    if self.running:
                        self._handle_wake()
                except Exception as exc:
                    print(f"Error handling wake: {exc}")
        finally:
            self._stop_file_watcher()
            signal.set_wakeup_fd(-1)
            self.wake_event.close()
            self.deadline_timer.close()

        print("Auto-theme daemon stopped")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Auto theme daemon")
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    parser.add_argument("--status", action="store_true", help="Show current status")
    parser.add_argument("--toggle", action="store_true", help="Send toggle signal to running daemon")
    parser.add_argument("--refresh", action="store_true", help="Send refresh signal to running daemon")
    args = parser.parse_args(argv)

    if args.status:
        if STATE_FILE.exists():
            state = json.loads(STATE_FILE.read_text())
            print(f"Current mode: {state.get('current_mode', 'unknown')}")
            print(f"Last change: {state.get('last_change', 'never')}")
            if state.get("manual_override_until"):
                print(f"Manual override until: {state['manual_override_until']}")
        else:
            print("No state file found")
        if ASTRAL_AVAILABLE:
            config = load_config()
            resolve_location_settings_into(config)
            daylight = daylight_window(config)
            print(f"Light mode starts: {daylight.starts_at.strftime('%H:%M')}")
            print(f"Light mode ends: {daylight.ends_at.strftime('%H:%M')}")
        return 0

    if args.toggle or args.refresh:
        import glob
        for pidfile in glob.glob(str(TMPDIR_PATH / "auto_theme_*.pid")):
            try:
                pid = int(Path(pidfile).read_text().strip())
                os.kill(pid, signal.SIGUSR1 if args.toggle else signal.SIGUSR2)
                print(f"Signal sent to PID {pid}")
                return 0
            except Exception:
                continue
        print("No running daemon found")
        return 0

    daemon = AutoThemeDaemon()
    if args.once:
        should_be_light, reason = daemon._should_be_light()
        return 0 if daemon._apply_mode("light" if should_be_light else "dark", reason) else 1

    pidfile = TMPDIR_PATH / f"auto_theme_{os.getpid()}.pid"
    pidfile.write_text(str(os.getpid()))
    try:
        daemon.run()
    finally:
        try:
            pidfile.unlink(missing_ok=True)
        except Exception:
            pass
    return 0
