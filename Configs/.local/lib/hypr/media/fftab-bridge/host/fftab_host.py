#!/usr/bin/env python3
"""fftab_host — native-messaging MPRIS bridge.

Receives per-tab media state from the fftab-bridge WebExtension over stdio
and owns one MPRIS bus name per media tab (each on its own DBus connection),
so playerctl/waybar see every tab as an independent player with an exact,
interpolated Position. MPRIS commands are forwarded back to the extension.
"""

import json
import struct
import sys
import threading
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_PREFIX = "org.mpris.MediaPlayer2.fftab_t"
OBJ_PATH = "/org/mpris/MediaPlayer2"
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
SEEK_SIGNAL_THRESHOLD = 2.0

NODE_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
    <method name="SetPosition">
      <arg name="TrackId" type="o" direction="in"/>
      <arg name="Position" type="x" direction="in"/>
    </method>
    <method name="OpenUri"><arg name="Uri" type="s" direction="in"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

_node_info = Gio.DBusNodeInfo.new_for_xml(NODE_XML)
_stdout_lock = threading.Lock()


def send_to_extension(payload: dict) -> None:
    data = json.dumps(payload).encode()
    with _stdout_lock:
        sys.stdout.buffer.write(struct.pack("<I", len(data)))
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def log(msg: str) -> None:
    print(f"fftab_host: {msg}", file=sys.stderr, flush=True)


class TabPlayer:
    def __init__(self, tab_id: int):
        self.tab_id = tab_id
        self.state = {
            "title": "",
            "url": "",
            "site": "",
            "status": "Paused",
            "duration": 0.0,
            "rate": 1.0,
        }
        self.anchor_pos = 0.0
        self.anchor_ts = time.monotonic()
        address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
        self.conn = Gio.DBusConnection.new_for_address_sync(
            address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None,
            None,
        )
        self.reg_ids = [
            self.conn.register_object(
                OBJ_PATH, iface, self._on_method_call, self._on_get_property, self._on_set_property
            )
            for iface in _node_info.interfaces
        ]
        self.owner_id = Gio.bus_own_name_on_connection(
            self.conn, BUS_PREFIX + str(tab_id), Gio.BusNameOwnerFlags.NONE, None, None
        )

    # --- state ---

    def position_seconds(self) -> float:
        pos = self.anchor_pos
        if self.state["status"] == "Playing":
            pos += (time.monotonic() - self.anchor_ts) * self.state["rate"]
        duration = self.state["duration"]
        if duration > 0:
            pos = min(pos, duration)
        return max(0.0, pos)

    def update(self, msg: dict) -> None:
        expected = self.position_seconds()
        new = {
            "title": str(msg.get("title", "")),
            "url": str(msg.get("url", "")),
            "site": str(msg.get("site", "")),
            "status": "Playing" if msg.get("status") == "Playing" else "Paused",
            "duration": max(0.0, float(msg.get("duration", 0.0) or 0.0)),
            "rate": float(msg.get("rate", 1.0) or 1.0),
        }
        position = max(0.0, float(msg.get("position", 0.0) or 0.0))

        changed = {}
        if new["status"] != self.state["status"]:
            changed["PlaybackStatus"] = GLib.Variant("s", new["status"])
        if new["rate"] != self.state["rate"]:
            changed["Rate"] = GLib.Variant("d", new["rate"])
        if (new["title"], new["url"], new["duration"], new["site"]) != (
            self.state["title"],
            self.state["url"],
            self.state["duration"],
            self.state["site"],
        ):
            changed["Metadata"] = self._metadata(new)

        seeked = abs(position - expected) > SEEK_SIGNAL_THRESHOLD
        self.state = new
        self.anchor_pos = position
        self.anchor_ts = time.monotonic()

        if changed:
            self.conn.emit_signal(
                None,
                OBJ_PATH,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                GLib.Variant("(sa{sv}as)", (PLAYER_IFACE, changed, [])),
            )
        if seeked:
            self.conn.emit_signal(
                None,
                OBJ_PATH,
                PLAYER_IFACE,
                "Seeked",
                GLib.Variant("(x)", (int(position * 1e6),)),
            )

    def destroy(self) -> None:
        if self.owner_id:
            Gio.bus_unown_name(self.owner_id)
            self.owner_id = 0
        for rid in self.reg_ids:
            self.conn.unregister_object(rid)
        self.reg_ids = []
        self.conn.close(None, None, None)

    # --- dbus ---

    def _metadata(self, state=None) -> GLib.Variant:
        s = state or self.state
        meta = {
            "mpris:trackid": GLib.Variant(
                "o", f"/org/mpris/MediaPlayer2/fftab/t{self.tab_id}"
            ),
            "xesam:title": GLib.Variant("s", s["title"]),
            "xesam:url": GLib.Variant("s", s["url"]),
            "xesam:artist": GLib.Variant("as", [s["site"]] if s["site"] else []),
        }
        if s["duration"] > 0:
            meta["mpris:length"] = GLib.Variant("x", int(s["duration"] * 1e6))
        return GLib.Variant("a{sv}", meta)

    def _on_get_property(self, conn, sender, path, iface, prop):
        if iface == ROOT_IFACE:
            return {
                "CanRaise": GLib.Variant("b", False),
                "CanQuit": GLib.Variant("b", False),
                "HasTrackList": GLib.Variant("b", False),
                "Identity": GLib.Variant("s", f"Firefox tab {self.tab_id}"),
                "SupportedUriSchemes": GLib.Variant("as", []),
                "SupportedMimeTypes": GLib.Variant("as", []),
            }.get(prop)
        return {
            "PlaybackStatus": GLib.Variant("s", self.state["status"]),
            "Rate": GLib.Variant("d", self.state["rate"]),
            "Metadata": self._metadata(),
            "Volume": GLib.Variant("d", 1.0),
            "Position": GLib.Variant("x", int(self.position_seconds() * 1e6)),
            "MinimumRate": GLib.Variant("d", 0.25),
            "MaximumRate": GLib.Variant("d", 4.0),
            "CanGoNext": GLib.Variant("b", False),
            "CanGoPrevious": GLib.Variant("b", False),
            "CanPlay": GLib.Variant("b", True),
            "CanPause": GLib.Variant("b", True),
            "CanSeek": GLib.Variant("b", True),
            "CanControl": GLib.Variant("b", True),
        }.get(prop)

    def _on_set_property(self, conn, sender, path, iface, prop, value):
        return True

    def _on_method_call(self, conn, sender, path, iface, method, params, invocation):
        command = None
        if method in ("Play", "Pause", "PlayPause", "Stop"):
            command = {"command": method.lower()}
        elif method == "Seek":
            command = {"command": "seek", "offset": params.unpack()[0] / 1e6}
        elif method == "SetPosition":
            command = {"command": "setposition", "position": params.unpack()[1] / 1e6}
        if command:
            send_to_extension({"type": "command", "tabId": self.tab_id, **command})
        invocation.return_value(None)


players: dict[int, TabPlayer] = {}


def dispatch(msg: dict) -> bool:
    try:
        tab_id = int(msg.get("tabId", -1))
        if tab_id < 0:
            return False
        if msg.get("type") == "update":
            player = players.get(tab_id)
            if player is None:
                player = players[tab_id] = TabPlayer(tab_id)
                log(f"registered {BUS_PREFIX}{tab_id}")
            player.update(msg)
        elif msg.get("type") == "removed":
            player = players.pop(tab_id, None)
            if player:
                player.destroy()
                log(f"released {BUS_PREFIX}{tab_id}")
    except Exception as exc:
        log(f"dispatch error: {exc!r}")
    return False


def stdin_reader(loop: GLib.MainLoop) -> None:
    stdin = sys.stdin.buffer
    while True:
        header = stdin.read(4)
        if len(header) < 4:
            break
        (length,) = struct.unpack("<I", header)
        data = stdin.read(length)
        if len(data) < length:
            break
        try:
            msg = json.loads(data)
        except json.JSONDecodeError:
            continue
        GLib.idle_add(dispatch, msg)
    GLib.idle_add(loop.quit)


def main() -> None:
    loop = GLib.MainLoop()
    threading.Thread(target=stdin_reader, args=(loop,), daemon=True).start()
    try:
        loop.run()
    finally:
        for player in players.values():
            player.destroy()


if __name__ == "__main__":
    main()
