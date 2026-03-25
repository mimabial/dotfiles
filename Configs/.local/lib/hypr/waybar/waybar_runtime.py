#!/usr/bin/env python3
import contextlib
import ctypes
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
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from pyutils.lock_paths import runtime_lock_path
from pyutils.xdg_base_dirs import xdg_runtime_dir, xdg_state_home
from waybar_assets import (
    generate_includes,
    refresh_waybar_assets,
    update_border_radius,
    update_config,
    update_global_css,
    update_icon_size,
    update_style,
    write_style_file,
)
from waybar_state import (
    ensure_state_file,
    get_state_value,
    list_layouts_json_text,
    synchronize_layout_state,
)
from waybar_shared import (
    CONFIG_WAYBAR_DIR,
    CONFIG_JSONC,
    DATA_WAYBAR_DIR,
    DUNST_SYNC_SCRIPT,
    STATE_FILE,
    WATCHED_SUFFIXES,
    atomic_write_text,
    logger,
    source_env_file,
)

WAYBAR_BIN = shutil.which("waybar")
if WAYBAR_BIN is None:
    logger.info("Waybar binary not found! Is waybar installed? Exiting...")
    print("Waybar binary not found! Is waybar installed? Exiting...")
    sys.exit(0)

WAYBAR_LOCK = runtime_lock_path("waybar")
WAYBAR_OP_LOCK = runtime_lock_path("waybar_op")
WAYBAR_WATCH_LOCK = runtime_lock_path("waybar_watch")
WAYBAR_WATCH_META = runtime_lock_path("waybar_watch_meta")
THEME_UPDATE_LOCK = runtime_lock_path("theme_update")
THEME_UPDATE_META = runtime_lock_path("theme_update_meta")



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
        except:
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


def signal_handler(sig, frame):
    kill_waybar()
    sys.exit(0)


def kill_waybar():
    """Kill waybar (wrapper for stop_waybar)."""
    stop_waybar()


@contextlib.contextmanager
def waybar_operation_lock():
    """Serialize Waybar process mutations across all control paths."""
    WAYBAR_OP_LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(WAYBAR_OP_LOCK, "a+") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def is_waybar_operation_locked():
    """Return True when another process is mutating Waybar state."""
    WAYBAR_OP_LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(WAYBAR_OP_LOCK, "a+") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    return False


def is_runtime_lock_held(lock_path):
    """Return True when another process currently holds an exclusive runtime lock."""
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with open(lock_path, "a+") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    return False


def run_waybar():
    """Run Waybar if not already running."""
    if not is_waybar_running_for_current_user():
        start_waybar()
    else:
        logger.debug("Waybar already running")


def is_waybar_running_for_current_user():
    """Check if Waybar is running for the current user."""
    return get_waybar_pid() is not None


def is_waybar_watcher_active():
    """Return True when the watcher currently owns Waybar restarts."""
    return is_runtime_lock_held(WAYBAR_WATCH_LOCK)


def read_waybar_watch_meta():
    """Read watcher metadata written by the active watch process."""
    return read_runtime_meta(WAYBAR_WATCH_META)


def restart_waybar():
    """Restart Waybar - skip if watcher is handling it."""
    if is_waybar_watcher_active():
        logger.debug("Watcher lock held - skipping direct restart")
        return

    # No watcher - do manual restart
    logger.debug("No watcher detected, restarting manually")
    with waybar_operation_lock():
        _stop_waybar_unlocked()
        _start_waybar_unlocked()


def restart_waybar_direct():
    """Restart Waybar immediately, even when the watcher is active."""
    logger.debug("Direct Waybar restart requested")
    with waybar_operation_lock():
        _stop_waybar_unlocked()
        _start_waybar_unlocked()


def sync_dunst_position(mode=None):
    if not os.path.exists(DUNST_SYNC_SCRIPT):
        return

    cmd = [DUNST_SYNC_SCRIPT]
    if mode:
        cmd.append(mode)
    try:
        subprocess.run(cmd, timeout=5, check=False)
        logger.debug(
            f"Synced dunst position with waybar ({mode or 'write-and-reload'})"
        )
    except Exception as exc:
        logger.warning(f"Failed to sync dunst position: {exc}")


def get_waybar_position():
    try:
        with open(CONFIG_JSONC, "r") as file:
            return json.load(file).get("position", "right")
    except Exception:
        return "right"


def read_focused_monitor_reserved():
    try:
        result = subprocess.run(
            ["hyprctl", "monitors", "-j"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        monitors = json.loads(result.stdout)
        if not monitors:
            return None
        monitor = next((item for item in monitors if item.get("focused")), monitors[0])
        reserved = monitor.get("reserved")
        if isinstance(reserved, list) and len(reserved) == 4:
            return reserved
    except Exception as exc:
        logger.debug(f"Failed to read monitor reserved edges: {exc}")
    return None


def wait_for_waybar_reserved_edge(position, timeout=2.0):
    edge_index = {"left": 0, "top": 1, "right": 2, "bottom": 3}.get(position)
    if edge_index is None:
        return False

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        reserved = read_focused_monitor_reserved()
        if reserved and reserved[edge_index] > 0:
            return True
        time.sleep(0.05)
    return False


def sync_dunst_position_after_waybar_restart():
    wait_for_waybar_reserved_edge(get_waybar_position())
    sync_dunst_position("--reload-only")


def kill_waybar_and_watcher():
    """Kill all Waybar instances and watcher scripts for the current user."""
    kill_waybar()
    logger.debug("Killed Waybar processes for current user.")

    try:
        watcher_pid = read_waybar_watch_pid()
        if watcher_pid and watcher_pid != os.getpid():
            os.kill(watcher_pid, signal.SIGTERM)
            wait_for_pid_exit(watcher_pid, 5.0)
            logger.debug(f"Stopped Waybar watcher PID {watcher_pid}")
    except Exception as e:
        logger.error(f"Error killing waybar.py processes: {e}")


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


def read_runtime_meta(lock_path):
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


def theme_update_lock_active(lock_path):
    return is_runtime_lock_held(lock_path)


def smart_reload_waybar(changed_files):
    """Reload waybar based on what changed."""
    # Only restart Waybar when its structure changes.
    # CSS updates (including theme.css) should not force a full restart, because
    # restarts reset module runtime state (e.g. idle_inhibitor activation).
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
            f"CSS files changed: {[Path(f).name for f in changed_files]}, full restart"
        )

    # Avoid SIGUSR2 reload: Waybar spawns defunct child processes on reload.
    with waybar_operation_lock():
        _stop_waybar_unlocked()
        _start_waybar_unlocked()


def watch_waybar():
    """Watch waybar configs with inotify or fallback to polling."""
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
            lock_exists = theme_update_lock_active(THEME_UPDATE_LOCK)
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
            lock_exists = theme_update_lock_active(THEME_UPDATE_LOCK)
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


def get_waybar_pid():
    """Get waybar PID if running, None otherwise."""
    pids = get_waybar_pids()
    if pids:
        return pids[0]
    return None


def read_waybar_lock_pid():
    """Read the PID currently recorded in WAYBAR_LOCK."""
    if not WAYBAR_LOCK.exists():
        return None
    try:
        return int(WAYBAR_LOCK.read_text().strip())
    except Exception:
        return None


def read_waybar_watch_pid():
    """Read the PID of the active watcher process from watcher metadata."""
    pid_raw = read_waybar_watch_meta().get("pid", "")
    try:
        return int(pid_raw)
    except (TypeError, ValueError):
        return None


def pid_is_zombie(pid):
    """Return True when pid exists but is a zombie."""
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        with open(f"/proc/{pid}/stat", "r") as file:
            data = file.read()
    except FileNotFoundError:
        return False
    except Exception as exc:
        logger.debug(f"Failed to read /proc/{pid}/stat: {exc}")
        return False

    rparen = data.rfind(")")
    if rparen == -1 or rparen + 2 >= len(data):
        return False
    state = data[rparen + 2 :].strip().split(" ", 1)[0]
    return state == "Z"


def pid_is_live_waybar(pid):
    """Return True when pid is a live Waybar process for the current user."""
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        if os.stat(f"/proc/{pid}").st_uid != os.getuid():
            return False
    except FileNotFoundError:
        return False
    except Exception as exc:
        logger.debug(f"Failed to stat /proc/{pid}: {exc}")
        return False

    if pid_is_zombie(pid):
        return False

    try:
        with open(f"/proc/{pid}/comm", "r") as file:
            return file.read().strip() == "waybar"
    except FileNotFoundError:
        return False
    except Exception as exc:
        logger.debug(f"Failed to read /proc/{pid}/comm: {exc}")
        return False


def is_waybar_running_or_starting():
    """Return True when Waybar is already visible or has been spawned by the lock owner."""
    if pid_is_live_waybar(read_waybar_lock_pid()):
        return True
    return is_waybar_running_for_current_user()


def wait_for_pid_exit(pid, timeout_seconds):
    """Wait for a PID to exit, using pidfd when available."""
    if not isinstance(pid, int) or pid <= 0:
        return True

    pidfd_open = getattr(os, "pidfd_open", None)
    if pidfd_open is not None:
        try:
            pidfd = pidfd_open(pid)
        except ProcessLookupError:
            return True
        except Exception as exc:
            logger.debug(f"pidfd_open failed for PID {pid}: {exc}")
        else:
            try:
                poller = select.poll()
                poller.register(pidfd, select.POLLIN)
                return bool(poller.poll(int(timeout_seconds * 1000)))
            finally:
                os.close(pidfd)

    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        time.sleep(0.05)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def get_waybar_pids():
    """Get all Waybar PIDs for the current user."""

    try:
        result = subprocess.run(
            ["pgrep", "-x", "waybar"], capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            pids = []
            for pid_str in result.stdout.strip().split():
                try:
                    pid = int(pid_str)
                except ValueError:
                    continue
                if pid_is_zombie(pid):
                    logger.debug(f"Ignoring zombie waybar PID {pid}")
                    continue
                pids.append(pid)
            return pids
        return []
    except Exception as e:
        logger.error(f"Error checking waybar PID: {e}")
        return []


def _start_waybar_unlocked():
    """Start Waybar. Caller must hold waybar_operation_lock()."""
    locked_pid = read_waybar_lock_pid()
    if pid_is_live_waybar(locked_pid):
        logger.debug(f"Waybar already starting or running (locked PID {locked_pid})")
        return

    running_pids = get_waybar_pids()
    if running_pids:
        if locked_pid in running_pids:
            logger.debug(f"Waybar already running (PID {locked_pid})")
        else:
            WAYBAR_LOCK.write_text(str(running_pids[0]))
            logger.debug(
                f"Waybar already running (PIDs {running_pids}), refreshed lock to {running_pids[0]}"
            )
        return

    # Ensure required include files exist before Waybar loads CSS.
    try:
        update_border_radius()
    except Exception as e:
        logger.debug(f"Failed to update border-radius.css before start: {e}")

    def _waybar_preexec():
        # Ensure Waybar auto-reaps child module execs to prevent zombies.
        signal.signal(signal.SIGCHLD, signal.SIG_IGN)

    try:
        proc = subprocess.Popen(
            [WAYBAR_BIN],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            preexec_fn=_waybar_preexec,
        )

        # Write lock file immediately
        WAYBAR_LOCK.write_text(str(proc.pid))
        logger.debug(f"Started waybar (PID {proc.pid})")

    except Exception as e:
        logger.error(f"Failed to start waybar: {e}")


def start_waybar():
    """Start waybar with lock file to prevent duplicates."""
    with waybar_operation_lock():
        _start_waybar_unlocked()


def _stop_waybar_unlocked():
    """Stop Waybar gracefully. Caller must hold waybar_operation_lock()."""
    pids = get_waybar_pids()
    if not pids:
        WAYBAR_LOCK.unlink(missing_ok=True)
        logger.debug("Waybar not running")
        return

    try:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
                logger.debug(f"Sent SIGTERM to waybar (PID {pid})")
            except ProcessLookupError:
                continue

        remaining_pids = [pid for pid in pids if not wait_for_pid_exit(pid, 5.0)]
        if not remaining_pids:
            logger.debug("Waybar stopped gracefully")
            WAYBAR_LOCK.unlink(missing_ok=True)
            return

        # Force kill if still alive
        if remaining_pids:
            logger.warning("Waybar didn't stop, sending SIGKILL")
            for pid in remaining_pids:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    continue
                wait_for_pid_exit(pid, 1.0)
            WAYBAR_LOCK.unlink(missing_ok=True)

    except ProcessLookupError:
        logger.debug("Waybar already stopped")
        WAYBAR_LOCK.unlink(missing_ok=True)
    except Exception as e:
        logger.error(f"Error stopping waybar: {e}")
        WAYBAR_LOCK.unlink(missing_ok=True)


def stop_waybar():
    """Stop waybar gracefully."""
    with waybar_operation_lock():
        _stop_waybar_unlocked()
