#!/usr/bin/env python3
"""Expose Blueman's live tray menu through Rofi."""

import html
import re
import subprocess
import sys

from gi.repository import Gio, GLib

BUS, PATH, API = "org.blueman.Applet", "/org/blueman/Applet", "org.blueman.Applet"


def clean(text: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", text)).replace("_", "")


def main() -> None:
    proxy = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None, BUS, PATH, API, None
    )
    try:
        menu = proxy.call_sync("GetMenu", None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
    except GLib.Error:
        subprocess.run(["notify-send", "Bluetooth", "Blueman applet is not running"], check=False)
        return

    entries = []

    def add(items, parent=(), prefix="", enabled=True):
        for index, item in enumerate(items):
            path = (*parent, index) if parent else (item["id"],)
            label = clean(item.get("text", ""))
            active = enabled and item.get("sensitive", True)
            if submenu := item.get("submenu"):
                add(submenu, path, f"{prefix}{label} › ", active)
            elif label and active:
                entries.append((f"{prefix}{label}", path))

    add(menu)
    result = subprocess.run(
        ["rofi", *sys.argv[1:]], input="\n".join(label for label, _ in entries),
        text=True, capture_output=True, check=False,
    )
    if result.returncode or not result.stdout.strip():
        return
    path = entries[int(result.stdout)][1]
    proxy.call_sync("ActivateMenuItem", GLib.Variant("(ai)", (path,)), Gio.DBusCallFlags.NONE, -1, None)


if __name__ == "__main__":
    main()
