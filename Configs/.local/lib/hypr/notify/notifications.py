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

# notify/archive.sh owns this format; the count is read straight off the files so
# the bar's two-second poll does not fork a shell just to compare timestamps.
ARCHIVE_DIR = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    / "hypr"
    / "notifications"
)

DUNST_DEST = "org.freedesktop.Notifications"
DUNST_PATH = "/org/freedesktop/Notifications"
DUNST_IFACE = "org.dunstproject.cmd0"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

try:
    BUS = Gio.bus_get_sync(Gio.BusType.SESSION, None)
except GLib.Error:
    BUS = None


def _run(cmd):
    return subprocess.run(
        cmd,
        check=True,
        capture_output=True,
        text=True,
        timeout=2,
    ).stdout.strip()


def _status_error(message):
    return {
        "text": "?",
        "alt": "error",
        "tooltip": message,
        "class": "error",
    }


# every query rides the one connection: no dunstctl shell, no dbus-send, no fork.
def _call(iface, method, params=None):
    return BUS.call_sync(
        DUNST_DEST, DUNST_PATH, iface, method, params, None,
        Gio.DBusCallFlags.NONE, 2000, None,
    ).unpack()[0]


def _get_dunst_properties():
    props = _call(PROPS_IFACE, "GetAll", GLib.Variant("(s)", (DUNST_IFACE,)))
    return (
        bool(props["paused"]),
        int(props["waitingLength"]),
        int(props["displayedLength"]),
        int(props["historyLength"]),
    )


def _get_history_items():
    return list(_call(DUNST_IFACE, "NotificationListHistory"))


def _extract_field(item, key):
    value = item.get(key, {})
    if isinstance(value, dict):
        return str(value.get("data", "")).strip()
    return str(value).strip()


def _archive_unread():
    try:
        seen = int((ARCHIVE_DIR / "seen").read_text().strip() or 0)
    except (OSError, ValueError):
        seen = 0

    count = 0
    try:
        with (ARCHIVE_DIR / "archive.jsonl").open() as handle:
            for line in handle:
                try:
                    if json.loads(line).get("ts", 0) > seen:
                        count += 1
                except (json.JSONDecodeError, AttributeError):
                    continue
    except OSError:
        return 0
    return count


def get_dunst_status():
    if BUS is None:
        return _status_error("no session bus")

    try:
        paused, waiting, displayed, history_count = _get_dunst_properties()
        history = _get_history_items()
    except (GLib.Error, KeyError, TypeError, ValueError):
        return _status_error("Failed to query dunst status")

    count = max(history_count, displayed + waiting, len(history))
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

    alt = "none"
    if paused:
        alt = "dnd-notification" if count > 0 else "dnd-none"
    elif count > 0:
        alt = "notification"
        if history:
            category = _extract_field(history[0], "category").lower()
            alt = category_map.get(category, alt)

    tooltip_lines = [
        "Notifications",
        "scroll-down: show latest from history",
        "left-click: toggle do not disturb",
        "middle-click: open menu",
        "right-click: clear notifications",
    ]

    if history:
        tooltip_lines.append("")
        for item in history[:8]:
            summary = _extract_field(item, "summary")
            body = _extract_field(item, "body")
            line = summary or body or "Notification"
            if summary and body and body != summary:
                line = f"{summary}: {body}"
            tooltip_lines.append(f"• {line}")

    return {
        "text": "",
        "alt": alt,
        "tooltip": "\n".join(tooltip_lines),
        "class": alt,
        "paused": paused,
        "unread": _archive_unread(),
    }


def toggle_dnd():
    _run(["dunstctl", "set-paused", "toggle"])
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
            pending = GLib.timeout_add(120, emit)

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
