#!/usr/bin/env python3
import ctypes
import json
import signal
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PR_SET_PDEATHSIG = 1
BUS_NAME = "org.hyprland.LauncherEntries"
OBJECT_PATH = "/org/hyprland/LauncherEntries"

# Updates carry only the properties that changed, so each app's state is merged.
entries = {}
owners = {}


def publish(app, entry, destination=None):
    count = entry.get("count", 0) if entry.get("count-visible") else 0
    progress = entry.get("progress", 0) if entry.get("progress-visible") else None
    update = json.dumps({"app": app, "count": count, "progress": progress})
    if not bus.is_closed():
        bus.emit_signal(destination, OBJECT_PATH, BUS_NAME, "Update", GLib.Variant("(s)", (update,)))


def on_update(_conn, sender, _path, _iface, _signal, params):
    uri, props = params.unpack()
    app = uri.removeprefix("application://").removesuffix(".desktop")
    if owners.get(app) != sender:
        entries[app] = {}
        owners[app] = sender
    entry = entries.setdefault(app, {})
    entry.update(props)
    publish(app, entry)


def on_owner_changed(_conn, _sender, _path, _iface, _signal, params):
    name, _old_owner, new_owner = params.unpack()
    if new_owner:
        return
    for app, owner in tuple(owners.items()):
        if owner == name:
            del owners[app]
            del entries[app]
            publish(app, {})


def on_refresh(_conn, sender, _path, _iface, _method, _params, invocation):
    for app, entry in entries.items():
        publish(app, entry, sender)
    invocation.return_value(None)


def on_entry_update(_conn, _sender, _path, _iface, _signal, params):
    print(params.unpack()[0], flush=True)


# GIO keeps only a weak reference to the shared bus: dropping this one closes it.
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
if sys.argv[1:] == ["serve"]:
    interface = Gio.DBusNodeInfo.new_for_xml(
        f'<node><interface name="{BUS_NAME}"><method name="Refresh"/>'
        '<signal name="Update"><arg type="s"/></signal></interface></node>')
    bus.register_object(OBJECT_PATH, interface.interfaces[0], on_refresh, None, None)
    bus.signal_subscribe(
        None, "com.canonical.Unity.LauncherEntry", "Update", None, None, Gio.DBusSignalFlags.NONE, on_update)
    bus.signal_subscribe(
        "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus",
        None, Gio.DBusSignalFlags.NONE, on_owner_changed)
    Gio.bus_own_name_on_connection(bus, BUS_NAME, Gio.BusNameOwnerFlags.NONE, None, None)
    Gio.bus_own_name_on_connection(bus, "com.canonical.Unity", Gio.BusNameOwnerFlags.NONE, None, None)
else:
    ctypes.CDLL(None).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    bus.signal_subscribe(
        BUS_NAME, BUS_NAME, "Update", OBJECT_PATH, None, Gio.DBusSignalFlags.NONE, on_entry_update)
    bus.call_sync(BUS_NAME, OBJECT_PATH, BUS_NAME, "Refresh", None, None, Gio.DBusCallFlags.NONE, -1, None)
GLib.MainLoop().run()
