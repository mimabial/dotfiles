#!/usr/bin/env python3
import ctypes
import json
import signal

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PR_SET_PDEATHSIG = 1

# Updates carry only the properties that changed, so each app's state is merged.
entries = {}


def on_update(_conn, _sender, _path, _iface, _signal, params):
    uri, props = params.unpack()
    app = uri.removeprefix("application://").removesuffix(".desktop")
    entry = entries.setdefault(app, {})
    entry.update(props)
    count = entry.get("count", 0) if entry.get("count-visible") else 0
    print(json.dumps({"app": app, "count": count}), flush=True)


ctypes.CDLL(None).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
# GIO keeps only a weak reference to the shared bus: dropping this one closes it.
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
bus.signal_subscribe(
    None, "com.canonical.Unity.LauncherEntry", "Update", None, None, Gio.DBusSignalFlags.NONE, on_update)
GLib.MainLoop().run()
