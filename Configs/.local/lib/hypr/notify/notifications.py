#!/usr/bin/env python3

import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils import child_process
from pyutils.xdg_base_dirs import xdg_state_home

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

# notify/archive.sh owns this format; the state is read straight off the files so
# each dunst event does not fork a shell just to compare timestamps.
ARCHIVE_DIR = (
    xdg_state_home()
    / "hypr"
    / "notifications"
)

DUNST_DEST = "org.freedesktop.Notifications"
DUNST_CALL_TIMEOUT_MS = 2000
EMIT_COALESCE_MS = 120
DUNST_PATH = "/org/freedesktop/Notifications"
DUNST_IFACE = "org.dunstproject.cmd0"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
CATEGORIES_WITH_BAR_ICON = frozenset(
    {"email", "chat", "warning", "error", "network", "battery", "update", "music", "volume"}
)

try:
    BUS = Gio.bus_get_sync(Gio.BusType.SESSION, None)
except GLib.Error:
    BUS = None


def _status_error():
    return {"text": "", "alt": "error", "class": "error"}


# every query rides the one connection: no dunstctl shell, no dbus-send, no fork.
def _call_dunst_dbus(iface, method, params=None):
    return BUS.call_sync(
        DUNST_DEST, DUNST_PATH, iface, method, params, None,
        Gio.DBusCallFlags.NONE, DUNST_CALL_TIMEOUT_MS, None,
    ).unpack()[0]


def read_dunst_pause_state():
    return bool(_call_dunst_dbus(PROPS_IFACE, "Get", GLib.Variant("(ss)", (DUNST_IFACE, "paused"))))


# the panel lists the archive, not dunst's history, so the icon follows it too
def read_archive_counts_and_latest_category():
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


def notification_indicator_status():
    if BUS is None:
        return _status_error()

    try:
        paused = read_dunst_pause_state()
    except (GLib.Error, TypeError, ValueError):
        return _status_error()

    total, unread, category = read_archive_counts_and_latest_category()
    category = category.lower()
    if not total:
        alt = "none"
    elif category in CATEGORIES_WITH_BAR_ICON:
        alt = f"{category}-notification"
    else:
        alt = "notification"

    return {"text": "", "alt": alt, "class": alt, "paused": paused, "unread": unread}


def toggle_dnd():
    child_process.run(
        ["dunstctl", "set-paused", "toggle"],
        check=True,
        capture_output=True,
        timeout=DUNST_CALL_TIMEOUT_MS / 1000,
    )
    if shutil.which("quickshell"):
        subprocess.run(
            ["quickshell", "ipc", "call", "indicators", "refresh", "dnd"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


# dunst marks every counter it exposes emits-change, and dunst's own script rule
# rewrites the archive on each notification, so the badge can follow events.
def watch_notification_indicator():
    loop = GLib.MainLoop()
    pending = 0

    def emit():
        nonlocal pending
        pending = 0
        try:
            sys.stdout.write(json.dumps(notification_indicator_status()) + "\n")
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
        watch_notification_indicator()
        return
    status = notification_indicator_status()
    sys.stdout.write(json.dumps(status) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
