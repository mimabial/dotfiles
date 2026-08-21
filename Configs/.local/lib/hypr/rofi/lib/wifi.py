#!/usr/bin/env python3
"""Expose nm-applet's live tray menu through Rofi."""

import re
import subprocess
import sys

from gi.repository import Gio, GLib

BUS = "org.freedesktop.network-manager-applet"
PATH = "/org/ayatana/NotificationItem/nm_applet/Menu"
API = "com.canonical.dbusmenu"


def clean(text: str) -> str:
    return re.sub(r"<[^>]+>", "", text).replace("_", "")


def main() -> None:
    try:
        proxy = Gio.DBusProxy.new_for_bus_sync(
            Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None, BUS, PATH, API, None
        )
        proxy.call_sync("AboutToShow", GLib.Variant("(i)", (0,)), Gio.DBusCallFlags.NONE, -1, None)
        menu = proxy.call_sync(
            "GetLayout", GLib.Variant("(iias)", (0, -1, [])), Gio.DBusCallFlags.NONE, -1, None
        ).unpack()[1][2]
    except GLib.Error:
        subprocess.run(["notify-send", "Network", "nm-applet is not running"], check=False)
        return

    entries = []

    def add(items, prefix="", enabled=True):
        for item_id, props, children in items:
            active = enabled and props.get("enabled", True)
            if not props.get("visible", True) or props.get("type") == "separator":
                continue
            label = clean(props.get("label", ""))
            if children:
                add(children, f"{prefix}{label} › ", active)
            elif label and active:
                mark = "✓ " if props.get("toggle-state") == 1 else ""
                entries.append((f"{mark}{prefix}{label}", item_id))

    add(menu)
    result = subprocess.run(
        ["rofi", *sys.argv[1:]], input="\n".join(label for label, _ in entries),
        text=True, capture_output=True, check=False,
    )
    if result.returncode or not result.stdout.strip():
        return
    try:
        item_id = entries[int(result.stdout)][1]
    except (ValueError, IndexError):
        return
    proxy.call_sync(
        "Event", GLib.Variant("(isvu)", (item_id, "clicked", GLib.Variant("i", 0), 0)),
        Gio.DBusCallFlags.NONE, -1, None,
    )


if __name__ == "__main__":
    main()
