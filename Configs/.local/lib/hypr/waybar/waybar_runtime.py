#!/usr/bin/env python3
"""Waybar process management.

Owns the start / stop / restart contract and the locks that make concurrent
control paths safe.

Restart-ownership protocol:
  - WAYBAR_OP_LOCK serializes process mutations across callers.
  - WAYBAR_LOCK names the live Waybar PID (refreshed on start, removed on
    successful stop).
  - WAYBAR_WATCH_LOCK is held by waybar_watch.watch_waybar while running.
    When held, restart_waybar() defers to the watcher so it can batch with
    file events. restart_waybar_direct() bypasses it for structural changes
    that have already signaled the watcher via
    THEME_UPDATE_META["waybar_reload"]="direct".

This module deliberately does not know about Dunst (waybar_dunst.py) or
file watching (waybar_watch.py) — both are downstream concerns.
"""
import contextlib
import fcntl
import os
import select
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from waybar_assets import update_border_radius
from waybar_shared import (
    CONFIG_WAYBAR_DIR,
    WAYBAR_LOCK,
    WAYBAR_OP_LOCK,
    WAYBAR_WATCH_LOCK,
    WAYBAR_WATCH_META,
    logger,
)

WAYBAR_BIN = shutil.which("waybar")
if WAYBAR_BIN is None:
    logger.info("Waybar binary not found! Is waybar installed? Exiting...")
    print("Waybar binary not found! Is waybar installed? Exiting...")
    sys.exit(0)


def signal_handler(sig, frame):
    stop_waybar()
    sys.exit(0)


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


def is_waybar_running_for_current_user():
    """Check if Waybar is running for the current user."""
    return get_waybar_pid() is not None


def is_waybar_watcher_active():
    """Return True when waybar_watch.watch_waybar is the current restart owner."""
    return is_runtime_lock_held(WAYBAR_WATCH_LOCK)


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


def kill_waybar_and_watcher():
    """Kill all Waybar instances and watcher scripts for the current user."""
    stop_waybar()
    logger.debug("Killed Waybar processes for current user.")

    try:
        watcher_pid = read_waybar_watch_pid()
        if watcher_pid and watcher_pid != os.getpid():
            os.kill(watcher_pid, signal.SIGTERM)
            wait_for_pid_exit(watcher_pid, 5.0)
            logger.debug(f"Stopped Waybar watcher PID {watcher_pid}")
    except Exception as e:
        logger.error(f"Error killing waybar.py processes: {e}")


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
    """Read the PID of the active watcher process from WAYBAR_WATCH_META.
    Inline parser to avoid importing waybar_watch (which imports from us)."""
    if not WAYBAR_WATCH_META.exists():
        return None
    try:
        for line in WAYBAR_WATCH_META.read_text().splitlines():
            line = line.strip()
            if line.startswith("pid="):
                return int(line.split("=", 1)[1].strip())
    except Exception:
        return None
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
            ["pgrep", "-u", str(os.getuid()), "-x", "waybar"],
            capture_output=True,
            text=True,
            check=False,
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


def _live_cursor_env():
    """os.environ with XCURSOR_*/HYPRCURSOR_* refreshed from gsettings.

    Cursor env freezes at each process's start; this watcher starts at login, so
    without this every (re)spawned Waybar would inherit the login-time cursor even
    after a theme switch. gsettings is the init-agnostic source the theme pipeline
    keeps current. Falls back to the inherited value when gsettings is unavailable.
    """
    env = dict(os.environ)

    def _gsettings(key):
        try:
            out = subprocess.run(
                ["gsettings", "get", "org.gnome.desktop.interface", key],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except Exception:
            return ""
        return out.stdout.strip().strip("'\"") if out.returncode == 0 else ""

    theme = _gsettings("cursor-theme")
    if theme:
        env["XCURSOR_THEME"] = env["HYPRCURSOR_THEME"] = theme
    size = _gsettings("cursor-size")
    if size.isdigit():
        env["XCURSOR_SIZE"] = env["HYPRCURSOR_SIZE"] = size
    return env


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

    # Avoid rewriting watched CSS on every start, or the watcher can trigger
    # a second restart from Waybar's own bootstrap path. The normal theme/apply
    # paths already refresh this file; only bootstrap it when it's missing.
    border_radius_css = CONFIG_WAYBAR_DIR / "includes" / "border-radius.css"
    if not border_radius_css.exists():
        try:
            update_border_radius()
        except Exception as e:
            logger.debug(f"Failed to bootstrap border-radius.css before start: {e}")

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
            env=_live_cursor_env(),
        )

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
