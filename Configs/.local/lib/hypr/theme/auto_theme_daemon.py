#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import signal
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Literal, Optional

HYPR_LIB_DIR = Path(__file__).resolve().parents[1]
if str(HYPR_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(HYPR_LIB_DIR))

from pyutils.lock_paths import runtime_lock_path
from auto_theme_support import (
    ASTRAL_AVAILABLE,
    CONFIG_FILE,
    NVIM_SETTINGS,
    STATE_FILE,
    TMPDIR_PATH,
    active_palette_file,
    get_sun_times,
    load_config,
    load_state,
    manual_override_deadline,
    next_sun_boundary,
    read_active_palette,
    read_color_variant_file,
    read_staterc,
    resolve_auto_location,
    resolve_hyprshell,
    resolve_wallpaper,
    save_state,
    set_state_value,
    state_config_file,
    state_home,
    wallpaper_state_file,
    watchdog_interval_seconds,
)
from auto_theme_watch import InotifyPathWatcher


class AutoThemeDaemon:
    def __init__(self):
        self.config = load_config()
        resolve_auto_location(self.config)
        self.state = load_state()
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

        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGUSR1, self._handle_toggle)
        signal.signal(signal.SIGUSR2, self._handle_refresh)

    def _active_palette_file(self) -> Path:
        return active_palette_file()

    def _state_config_file(self) -> Path:
        return state_config_file()

    def _theme_update_lock_file(self) -> Path:
        return runtime_lock_path("theme_update")

    def _theme_update_locked(self) -> bool:
        lock_file = self._theme_update_lock_file()
        lock_file.parent.mkdir(parents=True, exist_ok=True)
        with lock_file.open("a+") as handle:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        return False

    def _watchdog_interval_seconds(self) -> float:
        return watchdog_interval_seconds(self.config)

    def _watched_paths(self) -> list[Path]:
        return [
            CONFIG_FILE,
            self._state_config_file(),
            state_home() / "hypr" / "staterc",
            state_home() / "hypr" / "color_variant",
            wallpaper_state_file(),
            self._active_palette_file(),
        ]

    def _on_watched_file_changed(self, changed_path: Path):
        with self._event_lock:
            if changed_path == CONFIG_FILE or changed_path == self._state_config_file():
                self._pending_config_reload = True
            else:
                self._pending_state_refresh = True
        self.wake_event.set()

    def _start_file_watcher(self):
        watcher = InotifyPathWatcher(self._on_watched_file_changed)
        if watcher.start(self._watched_paths()):
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
        self.config = load_config()
        resolve_auto_location(self.config)

    @staticmethod
    def _color_source(staterc_values: dict) -> Literal["theme", "pywal"]:
        source = staterc_values.get("selected_color_source")
        if source in ("theme", "pywal"):
            return source
        return "theme" if staterc_values.get("selected_color_mode") in (None, "0") else "pywal"

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

        sunrise, sunset = get_sun_times(self.config, now.date())
        is_daytime = sunrise <= now <= sunset
        reason = f"sun ({'day' if is_daytime else 'night'}, rise={sunrise.strftime('%H:%M')}, set={sunset.strftime('%H:%M')})"
        return is_daytime, reason

    def _is_auto_mode(self) -> bool:
        raw = read_staterc().get("selected_color_mode")
        try:
            return int(raw) == 1 if raw is not None else False
        except ValueError:
            return False

    def _apply_mode(self, mode: Literal["light", "dark"], reason: str):
        if mode == self.state["current_mode"]:
            if self._is_auto_mode():
                if self.config["control_nvim"]:
                    self._reconcile_nvim(mode)
                if self.config["control_hyprland"]:
                    current_color_variant = read_color_variant_file()
                    staterc_values = read_staterc()
                    if current_color_variant != mode or not self._active_palette_matches(mode, staterc_values):
                        if self._theme_update_locked():
                            return
                        self._apply_hyprland(mode)
            return

        print(f"[{datetime.now().strftime('%H:%M:%S')}] Switching to {mode} mode ({reason})")
        self.state["current_mode"] = mode
        self.state["last_change"] = datetime.now().isoformat()
        save_state(self.state)

        if not self._is_auto_mode():
            print("Auto mode inactive, skipping target updates")
            return

        if self.config["control_nvim"]:
            self._apply_nvim(mode)
        if self.config["control_hyprland"]:
            self._apply_hyprland(mode)

    def _reconcile_nvim(self, mode: Literal["light", "dark"]):
        try:
            if NVIM_SETTINGS.exists():
                settings = json.loads(NVIM_SETTINGS.read_text())
                if settings.get("background") == mode:
                    return
        except Exception:
            pass
        self._apply_nvim(mode)

    def _apply_nvim(self, mode: Literal["light", "dark"]):
        try:
            settings = json.loads(NVIM_SETTINGS.read_text()) if NVIM_SETTINGS.exists() else {}
            settings["background"] = mode
            NVIM_SETTINGS.parent.mkdir(parents=True, exist_ok=True)
            NVIM_SETTINGS.write_text(json.dumps(settings))
        except Exception as exc:
            print(f"Warning: Failed to update Neovim: {exc}")

    def _pair_theme_for(self, current_theme: Optional[str], mode: str) -> Optional[str]:
        hyprshell = resolve_hyprshell()
        if not hyprshell or not current_theme:
            return current_theme
        try:
            result = subprocess.run(
                [hyprshell, "theme/pairs", "--pair-for", current_theme, mode],
                capture_output=True,
                text=True,
                timeout=10,
            )
            target = result.stdout.strip()
            if result.returncode == 0 and target:
                return target
        except Exception as exc:
            print(f"Warning: pair resolution failed: {exc}")
        return current_theme

    def _switch_theme(self, theme: str) -> bool:
        hyprshell = resolve_hyprshell()
        if not hyprshell:
            print("Warning: hyprshell not found, cannot switch theme")
            return False
        try:
            result = subprocess.run(
                [hyprshell, "theme/theme.switch", "-s", theme, "--quiet"],
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

    def _apply_hyprland(self, mode: Literal["light", "dark"]):
        try:
            staterc_values = read_staterc()
            color_source = self._color_source(staterc_values)
            current_theme = staterc_values.get("HYPR_THEME")
            target_theme = self._pair_theme_for(current_theme, mode)
            if target_theme and current_theme and target_theme != current_theme:
                self._switch_theme(target_theme)
                return

            set_state_value("BACKGROUND_MODE", mode, "staterc")
            set_state_value("", mode, "color_variant")

            hypr_theme = shutil.which("hypr-theme")
            if not hypr_theme:
                candidate = Path.home() / ".local" / "bin" / "hypr-theme"
                if candidate.exists():
                    hypr_theme = str(candidate)
            if not hypr_theme:
                print("Warning: hypr-theme not found, cannot apply colors")
                return

            env = os.environ.copy()
            env_path = env.get("PATH", "")
            env["PATH"] = f"{Path.home() / '.local' / 'bin'}:{env_path}"
            if staterc_values.get("HYPR_THEME"):
                env["HYPR_THEME"] = staterc_values["HYPR_THEME"]

            if color_source == "theme":
                if not current_theme:
                    print("Warning: Could not resolve current theme for palette update")
                    return
                command = [hypr_theme, "apply", current_theme]
            else:
                wallpaper = resolve_wallpaper(staterc_values)
                if not wallpaper or not wallpaper.exists():
                    print("Warning: Could not resolve current wallpaper for pywal update")
                    return
                command = [hypr_theme, "wallpaper", "--variant", mode, str(wallpaper)]

            result = subprocess.run(
                command,
                env=env,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "").strip()
                print(f"Warning: Failed to apply hypr-theme colors: {detail or 'unknown error'}")
        except Exception as exc:
            print(f"Warning: Failed to update Hyprland: {exc}")

    def _handle_signal(self, signum, frame):
        print(f"\nReceived signal {signum}, shutting down...")
        self.running = False
        self.stop_event.set()
        self.wake_event.set()

    def _handle_toggle(self, signum, frame):
        with self._event_lock:
            self._pending_toggle = True
        self.wake_event.set()

    def _handle_refresh(self, signum, frame):
        with self._event_lock:
            self._pending_refresh = True
        self.wake_event.set()

    def _apply_toggle(self):
        new_mode = "dark" if self.state["current_mode"] == "light" else "light"
        if self.config["manual_override_duration"] > 0:
            override_until = datetime.now() + timedelta(minutes=self.config["manual_override_duration"])
            self.state["manual_override_until"] = override_until.isoformat()
            print(f"Manual override until {override_until.strftime('%H:%M')}")
        self._apply_mode(new_mode, "manual_toggle")

    def _apply_refresh(self):
        print("Force refresh requested")
        self.state["manual_override_until"] = None
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", reason)

    def run(self):
        print(f"Auto-theme daemon started (PID: {os.getpid()})")
        print(f"  Location: {self.config['latitude']}, {self.config['longitude']}")
        print(f"  Watchdog interval: {self._watchdog_interval_seconds():g}s")

        self._start_file_watcher()
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", reason)
        now = datetime.now()
        self._watchdog_due_at = now + timedelta(seconds=self._watchdog_interval_seconds())

        try:
            while self.running:
                try:
                    now = datetime.now()
                    sun_due_at = next_sun_boundary(self.config, now)
                    override_due_at = manual_override_deadline(self.state)

                    deadlines = []
                    if self._watchdog_due_at is not None:
                        deadlines.append(self._watchdog_due_at)
                    if sun_due_at is not None:
                        deadlines.append(sun_due_at)
                    if override_due_at is not None:
                        deadlines.append(override_due_at)

                    timeout = None
                    if deadlines:
                        timeout = max(0.0, min((deadline - now).total_seconds() for deadline in deadlines))

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
                except Exception as exc:
                    print(f"Error in main loop: {exc}")
                    time.sleep(5)
        finally:
            self._stop_file_watcher()

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
            daemon = AutoThemeDaemon()
            sunrise, sunset = get_sun_times(daemon.config)
            print(f"Sunrise: {sunrise.strftime('%H:%M')}")
            print(f"Sunset: {sunset.strftime('%H:%M')}")
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
        daemon._apply_mode("light" if should_be_light else "dark", reason)
        return 0

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
