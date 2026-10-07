#!/usr/bin/env python3

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

# notify/archive.sh owns this format; the state is read straight off the files so
# each dunst event does not fork a shell just to compare timestamps.
ARCHIVE_DIR = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    / "hypr"
    / "notifications"
)

DUNST_DEST = "org.freedesktop.Notifications"
DUNST_CALL_TIMEOUT_MS = 2000
EMIT_COALESCE_MS = 120
DUNST_PATH = "/org/freedesktop/Notifications"
DUNST_IFACE = "org.dunstproject.cmd0"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

try:
    BUS = Gio.bus_get_sync(Gio.BusType.SESSION, None)
except GLib.Error:
    BUS = None


def _run_dunstctl(command):
    return subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=2,
    ).stdout.strip()


def _status_error():
    return {"text": "", "alt": "error", "class": "error"}


# every query rides the one connection: no dunstctl shell, no dbus-send, no fork.
def _call_dunst_dbus(iface, method, params=None):
    return BUS.call_sync(
        DUNST_DEST, DUNST_PATH, iface, method, params, None,
        Gio.DBusCallFlags.NONE, DUNST_CALL_TIMEOUT_MS, None,
    ).unpack()[0]


def _get_paused():
    return bool(_call_dunst_dbus(PROPS_IFACE, "Get", GLib.Variant("(ss)", (DUNST_IFACE, "paused"))))


# the panel lists the archive, not dunst's history, so the icon follows it too
def _archive_state():
    try:
        seen = int((ARCHIVE_DIR / "seen").read_text().strip() or 0)
    except (OSError, ValueError):
        seen = 0

    total = unread = 0
    category = ""
    try:
        with (ARCHIVE_DIR / "archive.jsonl").open() as handle:
            for line in handle:
                try:
                    entry = json.loads(line)
                    unread += entry.get("ts", 0) > seen
                except (json.JSONDecodeError, AttributeError):
                    continue
                total += 1
                category = entry.get("category", "")
    except OSError:
        pass
    return total, unread, category


def get_dunst_status():
    if BUS is None:
        return _status_error()

    try:
        paused = _get_paused()
    except (GLib.Error, TypeError, ValueError):
        return _status_error()

    total, unread, category = _archive_state()
    category_map = {
        "email": "email-notification",
        "chat": "chat-notification",
        "warning": "warning-notification",
        "error": "error-notification",
        "network": "network-notification",
        "battery": "battery-notification",
        "update": "update-notification",
        "music": "music-notification",
        "volume": "volume-notification",
    }

    alt = category_map.get(category.lower(), "notification") if total else "none"

    return {"text": "", "alt": alt, "class": alt, "paused": paused, "unread": unread}


def toggle_dnd():
    _run_dunstctl(["dunstctl", "set-paused", "toggle"])
    if shutil.which("quickshell"):
        subprocess.run(
            ["quickshell", "ipc", "call", "indicators", "refresh", "dnd"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


# dunst marks every counter it exposes emits-change, and dunst's own script rule
# rewrites the archive on each notification, so the badge can follow events.
def watch():
    loop = GLib.MainLoop()
    pending = 0

    def emit():
        nonlocal pending
        pending = 0
        try:
            sys.stdout.write(json.dumps(get_dunst_status()) + "\n")
            sys.stdout.flush()
        except OSError:
            loop.quit()
        return GLib.SOURCE_REMOVE

    # one notification moves several counters and touches the archive; coalesce
    def schedule(*_):
        nonlocal pending
        if not pending:
            pending = GLib.timeout_add(EMIT_COALESCE_MS, emit)

    if BUS is not None:
        BUS.signal_subscribe(
            DUNST_DEST, PROPS_IFACE, "PropertiesChanged", DUNST_PATH, None,
            Gio.DBusSignalFlags.NONE, schedule,
        )
    monitor = None
    if ARCHIVE_DIR.is_dir():
        monitor = Gio.File.new_for_path(str(ARCHIVE_DIR)).monitor_directory(
            Gio.FileMonitorFlags.NONE, None
        )
        monitor.connect("changed", schedule)
    emit()
    loop.run()


def main():
    if sys.argv[1:] == ["--toggle"]:
        toggle_dnd()
        return
    if sys.argv[1:] == ["--watch"]:
        watch()
        return
    status = get_dunst_status()
    sys.stdout.write(json.dumps(status) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
