#!/usr/bin/env python3
"""Render all BlueZ controllers for Waybar."""

import json
import sys

from gi.repository import Gio, GLib

ADAPTER = "org.bluez.Adapter1"
DEVICE = "org.bluez.Device1"
BATTERY = "org.bluez.Battery1"


def render(objects, status=False):
    adapters = {}
    for path, interfaces in objects.items():
        if props := interfaces.get(ADAPTER):
            adapters[path] = {
                "name": props.get("Alias", props.get("Address", path)),
                "powered": props.get("Powered", False),
                "discoverable": props.get("Discoverable", False),
                "discovering": props.get("Discovering", False),
                "devices": [],
            }
    for interfaces in objects.values():
        props = interfaces.get(DEVICE)
        if props and props.get("Connected") and props.get("Adapter") in adapters:
            battery = interfaces.get(BATTERY, {}).get("Percentage")
            adapters[props["Adapter"]]["devices"].append(
                (props.get("Alias", props.get("Address", "Unknown")), battery)
            )

    connected = [
        device for adapter in adapters.values() for device in adapter["devices"]
    ]
    if status:
        if len(connected) == 1 and connected[0][1] is not None:
            return f"<small><b>{connected[0][1]}</b></small>"
        return f"<b>{len(connected)}</b>" if connected else ""

    if not adapters:
        return json.dumps(
            {"text": "󰂲", "class": "off", "tooltip": "No Bluetooth controller"}
        )
    powered = any(adapter["powered"] for adapter in adapters.values())
    text, css = ("", "on") if powered else ("", "disabled")
    if connected:
        text, css = "<b>󰂱</b>", "connected"
    if any(adapter["discoverable"] for adapter in adapters.values()):
        css = "discoverable"
    if any(adapter["discovering"] for adapter in adapters.values()):
        css = "discovering"

    lines = []
    for adapter in sorted(adapters.values(), key=lambda item: item["name"].casefold()):
        lines.extend(
            (
                "<b>Controller</b>",
                adapter["name"],
                "<b>Bluetooth</b>",
                f"Powered {str(adapter['powered']).lower()}",
                "<b>Connected</b>",
            )
        )
        lines.extend(
            f"{name} {battery}%" if battery is not None else name
            for name, battery in adapter["devices"]
        )
        if not adapter["devices"]:
            lines[-1] += " none"
    return json.dumps(
        {"text": text, "class": css, "tooltip": "\n".join(lines)}, ensure_ascii=False
    )


def main():
    proxy = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SYSTEM,
        Gio.DBusProxyFlags.NONE,
        None,
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
        None,
    )
    try:
        objects = proxy.call_sync(
            "GetManagedObjects", None, Gio.DBusCallFlags.NONE, -1, None
        ).unpack()[0]
    except GLib.Error:
        objects = {}
    print(render(objects, "--status" in sys.argv))


if __name__ == "__main__":
    main()
