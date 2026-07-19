#!/usr/bin/env python3
"""File-watcher process for live Waybar config reloads.

Long-running daemon kicked off by `waybar.py --watch`. Uses inotify when
available (via ctypes) and falls back to polling when libc/inotify aren't
usable. Holds WAYBAR_WATCH_LOCK while running so the apply path can detect
its presence and defer its own restarts.

Restart-ownership protocol (see also: doc-block above restart_waybar in
waybar_runtime.py):
  - Layout/apply paths can write THEME_UPDATE_META["waybar_reload"] = "direct"
    when they perform their own restart.
  - Theme apply writes waybar_reload=css-hot and relies on Waybar's
    reload_style_on_change for CSS-only theme files.
  - This watcher reads THEME_UPDATE_META on every loop iteration; when it
    sees waybar_reload=direct, it discards pending events instead of
    restarting again. css-hot events are still classified by smart_reload_waybar.
  - During THEME_UPDATE_LOCK, events are batched until the lock releases.
"""
import contextlib
import ctypes
import fcntl
import os
import select
import signal
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from pyutils.xdg_base_dirs import xdg_runtime_dir
from waybar_runtime import (
    get_waybar_pid,
    is_waybar_operation_locked,
    is_waybar_running_or_starting,
    is_runtime_lock_held,
    signal_handler,
    start_waybar,
    waybar_operation_lock,
    _start_waybar_unlocked,
    _stop_waybar_unlocked,
)
from waybar_shared import (
    CONFIG_WAYBAR_DIR,
    DATA_WAYBAR_DIR,
    THEME_UPDATE_LOCK,
    THEME_UPDATE_META,
    WATCHED_SUFFIXES,
    WAYBAR_WATCH_LOCK,
    WAYBAR_WATCH_META,
    atomic_write_text,
    logger,
)

# Theme-generated CSS files Waybar hot-reloads automatically. When ONLY these
# files changed, the watcher skips the restart.
#
# CONTRACT: theme/ writers must keep this list in sync with the set of CSS
# files they emit during a theme switch. Adding a new theme-generated CSS
# without updating this list will cause an unnecessary Waybar restart on
# every theme switch.
THEME_ONLY_CSS_PATHS = {
    CONFIG_WAYBAR_DIR / "colors.css",
    CONFIG_WAYBAR_DIR / "theme.generated.css",
    CONFIG_WAYBAR_DIR / "includes" / "border-radius.css",
    CONFIG_WAYBAR_DIR / "includes" / "font.css",
}


class InotifyWatcher:
    """Native inotify watcher using ctypes."""

    IN_MODIFY = 0x00000002
    IN_ATTRIB = 0x00000004
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100

    def __init__(self):
        try:
            self.libc = ctypes.CDLL("libc.so.6")
            self.fd = self.libc.inotify_init()
            if self.fd < 0:
                raise OSError("inotify_init failed")
            self.watches = {}
        except (AttributeError, OSError):
            self.fd = None

    def add_watch(self, path, mask):
        if self.fd is None:
            return
        wd = self.libc.inotify_add_watch(self.fd, path.encode(), mask)
        if wd >= 0:
            self.watches[wd] = path

    def read_events(self, timeout=1.0):
        if self.fd is None:
            return []

        r, _, _ = select.select([self.fd], [], [], timeout)
        if not r:
            return []

        events = []
        buf = os.read(self.fd, 4096)
        i = 0
        while i < len(buf):
            wd, mask, cookie, length = struct.unpack_from("iIII", buf, i)
            i += 16
            name = buf[i : i + length].rstrip(b"\0").decode("utf-8", errors="ignore")
            i += length
            if wd in self.watches:
                events.append(os.path.join(self.watches[wd], name))
        return events


def read_runtime_meta(lock_path):
    """Read a `key=value\\n` runtime metadata file. Used for the watcher's
    own meta and for the theme_update meta the apply path writes.

    Sibling readers — see waybar/STATE.md:
      - waybar_state.get_state_value (Python, staterc, no quote stripping)
      - waybar.state.common.sh:waybar_state_value (Bash, staterc + env-overrides,
        strips quotes and `export`)
    """
    meta = {}
    try:
        with open(lock_path, "r") as file:
            for line in file:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                meta[key] = value
    except FileNotFoundError:
        return {}
    except Exception as exc:
        logger.debug(f"Failed to read theme update metadata: {exc}")
        return {}

    return meta


def read_waybar_watch_meta():
    """Read the watcher's own meta file (PID, started, cmd)."""
    return read_runtime_meta(WAYBAR_WATCH_META)


def is_waybar_watcher_active():
    """Return True when the watcher currently owns Waybar restarts."""
    return is_runtime_lock_held(WAYBAR_WATCH_LOCK)


def _is_relevant_waybar_path(path):
    name = path.name
    if not name:
        return False
    if name.startswith("."):
        return False
    if name.endswith("~") or name.endswith(".swp"):
        return False
    return path.suffix.lower() in WATCHED_SUFFIXES


def filter_waybar_events(events):
    filtered = []
    for event in events:
        try:
            path = Path(event)
        except Exception:
            continue
        if _is_relevant_waybar_path(path):
            filtered.append(str(path))
    return filtered


def poll_waybar_events(directories, last_mtimes):
    events = []
    for directory in directories:
        if not directory.exists():
            continue
        try:
            entries = list(directory.iterdir())
        except FileNotFoundError:
            continue
        for path in entries:
            if not path.is_file():
                continue
            if not _is_relevant_waybar_path(path):
                continue
            key = str(path)
            try:
                mtime = path.stat().st_mtime
            except FileNotFoundError:
                continue
            prev = last_mtimes.get(key)
            if prev is None:
                last_mtimes[key] = mtime
                continue
            if mtime != prev:
                last_mtimes[key] = mtime
                events.append(str(path))
    for key in list(last_mtimes.keys()):
        if not Path(key).exists():
            last_mtimes.pop(key, None)
    return events


def get_watch_interval_seconds():
    raw_interval = os.getenv("WAYBAR_WATCH_INTERVAL", "").strip()
    if raw_interval:
        try:
            interval = float(raw_interval)
            if interval > 0:
                return interval
        except ValueError:
            logger.warning(
                f"Invalid WAYBAR_WATCH_INTERVAL='{raw_interval}', using default"
            )
    return 0.2


def is_theme_only_css_change(changed_files):
    """Return True when every change is a theme-generated CSS file Waybar hot-reloads."""
    if not changed_files:
        return False

    for changed_file in changed_files:
        path = Path(changed_file)
        if path.suffix.lower() != ".css":
            return False
        if path not in THEME_ONLY_CSS_PATHS:
            return False

    return True


def smart_reload_waybar(changed_files):
    """Reload waybar based on what changed."""
    if is_theme_only_css_change(changed_files):
        logger.debug(
            "Ignoring theme-only CSS changes already covered by Waybar style hot reload: "
            f"{[Path(f).name for f in changed_files]}"
        )
        return

    # Track whether a structural file changed for logging/diagnostics.
    # In practice we always do a full restart here, because SIGUSR2-based reloads
    # have proven unreliable and can leave defunct child processes behind.
    structural_files = {"config.jsonc", "includes.json"}

    needs_restart = any(Path(f).name in structural_files for f in changed_files)

    pid = get_waybar_pid()
    if not pid:
        start_waybar()
        return

    if needs_restart:
        logger.debug(
            f"Structural files changed: {[Path(f).name for f in changed_files]}, full restart"
        )
    else:
        logger.debug(
            f"Non-structural Waybar files changed: {[Path(f).name for f in changed_files]}, full restart"
        )

    # Avoid SIGUSR2 reload: Waybar can spawn defunct child processes on reload.
    with waybar_operation_lock():
        _stop_waybar_unlocked()
        _start_waybar_unlocked()


def watch_waybar():
    """Watch waybar configs with inotify or fallback to polling."""
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)

    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    waybar_dir = CONFIG_WAYBAR_DIR
    includes_dir = waybar_dir / "includes"
    shared_waybar_dir = DATA_WAYBAR_DIR
    watch_dirs = [waybar_dir, includes_dir, shared_waybar_dir]
    WAYBAR_WATCH_LOCK.parent.mkdir(parents=True, exist_ok=True)
    watcher_lock_file = open(WAYBAR_WATCH_LOCK, "a+")
    try:
        fcntl.flock(watcher_lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        watcher_lock_file.close()
        logger.warning("Another Waybar watcher is already active; exiting")
        return
    atomic_write_text(
        WAYBAR_WATCH_META,
        f"pid={os.getpid()}\nstarted={int(time.time())}\ncmd=waybar.py --watch\n",
    )

    try:
        watcher = InotifyWatcher()
        use_polling = watcher.fd is None
        if use_polling:
            logger.warning("inotify unavailable, using polling for Waybar config reloads")
        else:
            mask = (
                InotifyWatcher.IN_CLOSE_WRITE
                | InotifyWatcher.IN_MOVED_TO
                | InotifyWatcher.IN_CREATE
                | InotifyWatcher.IN_ATTRIB
            )
            watcher.add_watch(str(waybar_dir), mask)
            watcher.add_watch(str(includes_dir), mask)
            watcher.add_watch(str(shared_waybar_dir), mask)
            logger.debug("Using inotify for file watching")

        # Batch events that occur during theme updates
        pending_events = []
        poll_state = {}
        watch_interval = get_watch_interval_seconds()
        theme_update_in_progress = False
        theme_update_meta = {}

        hidden_state_file = Path(xdg_runtime_dir()) / "waybar-hidden"

        while True:
            lock_exists = is_runtime_lock_held(THEME_UPDATE_LOCK)
            if (
                not lock_exists
                and not is_waybar_operation_locked()
                and not is_waybar_running_or_starting()
                and not hidden_state_file.exists()
            ):
                start_waybar()

            # Detect start of theme update
            if lock_exists and not theme_update_in_progress:
                logger.debug("Theme update started, batching events")
                theme_update_in_progress = True
                pending_events = []
                theme_update_meta = read_runtime_meta(THEME_UPDATE_META)

            if use_polling:
                events = poll_waybar_events(watch_dirs, poll_state)
                time.sleep(watch_interval)
            else:
                events = watcher.read_events(timeout=watch_interval)
                while events:
                    more_events = watcher.read_events(timeout=0)
                    if not more_events:
                        break
                    events.extend(more_events)

            events = filter_waybar_events(events)
            if events:
                pending_events.extend(events)

            # Detect end of theme update
            lock_exists = is_runtime_lock_held(THEME_UPDATE_LOCK)
            if not lock_exists and theme_update_in_progress:
                theme_update_in_progress = False

            if theme_update_in_progress:
                continue

            if not pending_events and not events:
                theme_update_meta = {}
                continue

            if pending_events and theme_update_meta.get("waybar_reload") == "direct":
                logger.debug(
                    "Skipping watcher reload; theme switch committed Waybar directly"
                )
                pending_events = []
                theme_update_meta = {}
                continue

            if pending_events:
                if is_waybar_operation_locked():
                    continue
                unique_events = list(dict.fromkeys(pending_events))
                logger.debug(f"Processing {len(unique_events)} file changes")
                smart_reload_waybar(unique_events)
                pending_events = []
                theme_update_meta = {}
    finally:
        WAYBAR_WATCH_META.unlink(missing_ok=True)
        try:
            fcntl.flock(watcher_lock_file.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass
        watcher_lock_file.close()
