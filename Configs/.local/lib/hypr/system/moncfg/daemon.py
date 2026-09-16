"""hyprmoncfgd: monitor profile daemon.

Speaks line-delimited JSON-RPC over a unix socket. Every frame carries
protocol_version 1; the panel silently drops frames that do not.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import threading
import time

from . import VERSION, hypr, profiles, render, workspaces

SOCKET_PATH = os.path.join(hypr.RUNTIME, "hyprmoncfgd.sock")
STATE_PATH = os.path.join(profiles.CONFIG_DIR, "state.json")
SCHEMA_VERSION = 1
PROTOCOL_VERSION = 1

# Fields the panel edits but that are derived from `mode`, so they are
# recomputed rather than written straight through.
DERIVED = ("width", "height", "refresh")


def log(message: str) -> None:
    """stdout is the daemon's log; the supervisor redirects it to a file."""
    print("hyprmoncfgd: %s %s" % (time.strftime("%Y/%m/%d %H:%M:%S"), message), flush=True)


def _iso(when: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(when)) + ".000Z"


def _load_state() -> dict:
    try:
        with open(STATE_PATH, encoding="utf-8") as handle:
            value = json.load(handle)
        if isinstance(value, dict):
            return value
    except (OSError, ValueError):
        pass
    return {}


def _save_state(state: dict) -> None:
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2)
    os.replace(tmp, STATE_PATH)


def apply_mode(output: dict) -> None:
    """Keep width/height/refresh consistent with whatever mode string is set."""
    mode = str(output.get("mode", ""))
    body = mode[:-2] if mode.endswith("Hz") else mode
    geometry, _, refresh = body.partition("@")
    width, _, height = geometry.partition("x")
    try:
        output["width"], output["height"] = int(width), int(height)
        if refresh:
            output["refresh"] = float(refresh)
    except ValueError:
        pass


def snap(profile: dict, key: str, distance: float) -> None:
    """Pull an output's edges onto a neighbour's when they land within tolerance."""
    if distance <= 0:
        return
    target = next((o for o in profile.get("outputs", []) if o.get("key") == key), None)
    if not target:
        return
    others = [
        o
        for o in profile.get("outputs", [])
        if o.get("key") != key and o.get("enabled", True)
    ]
    for axis, size in (("x", "width"), ("y", "height")):
        start = target.get(axis, 0)
        end = start + target.get(size, 0)
        candidates = []
        for other in others:
            other_start = other.get(axis, 0)
            other_end = other_start + other.get(size, 0)
            candidates += [
                (abs(start - other_start), other_start),
                (abs(start - other_end), other_end),
                (abs(end - other_start), other_start - target.get(size, 0)),
                (abs(end - other_end), other_end - target.get(size, 0)),
            ]
        if candidates:
            delta, value = min(candidates, key=lambda item: item[0])
            if delta <= distance:
                target[axis] = int(value)


def edit_profile(profile: dict, edit: dict) -> dict:
    """Apply one panel edit to a draft profile and hand the draft back."""
    draft = json.loads(json.dumps(profile or {}))
    draft.setdefault("outputs", [])
    edit = edit or {}

    if isinstance(edit.get("workspaces"), dict):
        draft["workspaces"] = edit["workspaces"]
        return draft

    key = str(edit.get("output_key", ""))
    output = next((o for o in draft["outputs"] if o.get("key") == key), None)
    if not output:
        return draft

    for field, value in edit.items():
        if field in ("output_key", "snap_distance") or field in DERIVED:
            continue
        output[field] = value
    if "mode" in edit:
        apply_mode(output)
    if edit.get("snap_distance"):
        snap(draft, key, float(edit["snap_distance"]))
    return draft


class Daemon:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.clients: list[socket.socket] = []
        self.state = _load_state()
        self.preview: dict | None = None
        self.monitors: list[dict] = []
        self.refresh_monitors()

    @property
    def unmanaged(self) -> bool:
        return bool(self.state.get("unmanaged", False))

    @property
    def auto(self) -> bool:
        return bool(self.state.get("auto", True))

    def set_state(self, **changes) -> None:
        self.state.update(changes)
        _save_state(self.state)

    def refresh_monitors(self) -> None:
        try:
            self.monitors = hypr.monitors()
        except (RuntimeError, OSError, ValueError):
            self.monitors = []

    def status_document(self) -> dict:
        stored = profiles.load_all()
        ranked = profiles.rank(self.monitors, stored)
        active = str(self.state.get("active_profile", ""))
        recommended = ranked[0] if ranked else None

        summaries = []
        for entry in ranked:
            summary = dict(entry)
            summary["active"] = summary["name"] == active
            summary["recommended"] = bool(recommended and summary["name"] == recommended["name"])
            summaries.append(summary)

        daemon: dict = {"running": True}
        if self.unmanaged:
            daemon["unmanaged"] = True
        if self.preview:
            daemon["preview"] = {
                "transaction_id": self.preview["id"],
                "deadline": self.preview["deadline"],
                "save_on_commit": self.preview["save_on_commit"],
                "profile_name": self.preview["profile"].get("name", ""),
                "profile": self.preview["profile"],
            }

        document = {
            "schema_version": SCHEMA_VERSION,
            "version": VERSION,
            "daemon": daemon,
            "monitors": [self.monitor_entry(m) for m in self.monitors],
            "profiles": summaries,
        }
        if active:
            document["active_profile"] = {"name": active}
        if recommended:
            document["recommended_profile"] = {
                "name": recommended["name"],
                "score": recommended["match_score"],
            }
        return document

    @staticmethod
    def monitor_entry(monitor: dict) -> dict:
        scale = monitor.get("scale", 1) or 1
        entry = {
            "name": monitor.get("name", ""),
            "description": monitor.get("description", ""),
            "make": monitor.get("make", ""),
            "model": monitor.get("model", ""),
            "enabled": not monitor.get("disabled", False),
            "focused": bool(monitor.get("focused", False)),
            "internal": monitor.get("name", "").startswith(("eDP", "LVDS", "DSI")),
            "mode": hypr.mode_string(
                monitor.get("width", 0), monitor.get("height", 0), monitor.get("refreshRate", 0)
            ),
            "width": int(monitor.get("width", 0)),
            "height": int(monitor.get("height", 0)),
            "logical_width": int(monitor.get("width", 0) / scale),
            "logical_height": int(monitor.get("height", 0) / scale),
            "refresh_rate": float(monitor.get("refreshRate", 0)),
            "scale": scale,
            "transform": int(monitor.get("transform", 0)),
            "x": int(monitor.get("x", 0)),
            "y": int(monitor.get("y", 0)),
        }
        if monitor.get("mirrorOf", "none") != "none":
            entry["mirror_of"] = monitor.get("mirrorOf", "")
        return entry

    def display_entry(self, monitor: dict) -> dict:
        scales = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3]
        return {
            "key": hypr.monitor_key(monitor),
            "name": monitor.get("name", ""),
            "description": monitor.get("description", ""),
            "available_modes": monitor.get("availableModes", []),
            "scale_options": scales,
            "physical_width": int(monitor.get("physicalWidth", 0)),
            "physical_height": int(monitor.get("physicalHeight", 0)),
            "internal": monitor.get("name", "").startswith(("eDP", "LVDS", "DSI")),
            "focused": bool(monitor.get("focused", False)),
            "dpms": bool(monitor.get("dpmsStatus", True)),
            "workspace": str((monitor.get("activeWorkspace") or {}).get("name", "")),
        }

    def editor_document(self) -> dict:
        stored = profiles.load_all()
        ranked = profiles.rank(self.monitors, stored)
        suggested = ranked[0]["name"] if ranked else ""
        active = str(self.state.get("active_profile", "")) or suggested

        source = next((p for p in stored if p.get("name") == active), None)
        draft = source or profiles.capture(active or "Draft", self.monitors)

        return {
            "displays": [self.display_entry(m) for m in self.monitors],
            "profile": draft,
            "profiles": stored,
            "profile_workspace_plans": {
                p.get("name", ""): workspaces.plan(p) for p in stored
            },
            "workspace_plan": workspaces.plan(draft),
            "source_profile": source.get("name", "") if source else "",
            "suggested_profile": suggested,
        }

    def broadcast(self) -> None:
        frame = json.dumps(
            {
                "type": "event",
                "protocol_version": PROTOCOL_VERSION,
                "event": "status",
                "data": self.status_document(),
            }
        ) + "\n"
        payload = frame.encode()
        with self.lock:
            for client in list(self.clients):
                try:
                    client.sendall(payload)
                except OSError:
                    self.clients.remove(client)

    def activate(self, profile: dict, remember: bool = True) -> None:
        render.apply(profile)
        if remember:
            self.set_state(active_profile=profile.get("name", ""))

    def available_monitors(self) -> list[dict]:
        """A closed lid takes the internal panel out of the running, unless it is
        the only display left -- switching then would leave nothing on screen."""
        if not hypr.lid_closed():
            return self.monitors
        external = [m for m in self.monitors if not hypr.is_internal(m)]
        return external or self.monitors

    def auto_switch(self) -> None:
        """Pick the best-matching profile for the connected set and apply it."""
        if self.unmanaged or not self.auto or self.preview:
            return
        self.refresh_monitors()
        match = profiles.best(self.available_monitors())
        if not match or match["name"] == self.state.get("active_profile"):
            return
        profile = profiles.by_name(match["name"])
        if profile:
            log("best profile %r score=%d lid=%s" % (
                match["name"], match["match_score"], "closed" if hypr.lid_closed() else "open"))
            self.activate(profile)
            log("applied profile: %s" % match["name"])

    def start_preview(self, params: dict) -> dict:
        if self.preview:
            raise ValueError("A display preview is already running")

        name = str(params.get("profile_name", ""))
        profile = params.get("profile") or (profiles.by_name(name) if name else None)
        if not isinstance(profile, dict) or not profile.get("outputs"):
            raise ValueError("No profile to preview")

        timeout = max(1, int(params.get("timeout_seconds", 10) or 10))
        # The rollback target is live state, not the stored profile: whatever is
        # on screen now is what the user gets back if they do nothing.
        previous = profiles.capture("__previous__", self.monitors)
        transaction = {
            "id": "preview-%d" % int(time.time() * 1000),
            "deadline": _iso(time.time() + timeout),
            "save_on_commit": bool(params.get("save_on_commit", False)),
            "profile": profile,
            "previous": previous,
        }
        self.preview = transaction
        self.activate(profile, remember=False)
        expiry = threading.Timer(timeout, self.expire_preview, (transaction["id"],))
        expiry.daemon = True
        expiry.start()
        return {"id": transaction["id"], "deadline": transaction["deadline"]}

    def finish_preview(self, transaction_id: str, keep: bool, save: bool) -> dict:
        transaction = self.preview
        if not transaction or (transaction_id and transaction_id != transaction["id"]):
            raise ValueError("That display preview is no longer running")
        self.preview = None

        if keep:
            profile = transaction["profile"]
            if save and profile.get("name"):
                profiles.save(profile)
            self.set_state(active_profile=profile.get("name", ""))
            render.apply(profile)
        else:
            render.apply(transaction["previous"])
        self.refresh_monitors()
        return {"transaction_id": transaction["id"], "kept": keep}

    def expire_preview(self, transaction_id: str) -> None:
        with self.lock:
            if not self.preview or self.preview["id"] != transaction_id:
                return
            self.finish_preview(transaction_id, keep=False, save=False)
        self.broadcast()

    def handle(self, method: str, params: dict, client: socket.socket):
        if method in ("subscribe", "status"):
            if method == "subscribe":
                with self.lock:
                    if client not in self.clients:
                        self.clients.append(client)
            self.refresh_monitors()
            return self.status_document(), False

        if method == "editor_state":
            self.refresh_monitors()
            return self.editor_document(), False

        if method == "edit_profile":
            draft = edit_profile(params.get("profile") or {}, params.get("edit") or {})
            return {"profile": draft, "workspace_plan": workspaces.plan(draft)}, False

        if method == "save":
            profile = params.get("profile")
            if not isinstance(profile, dict) or not str(profile.get("name", "")).strip():
                raise ValueError("A profile needs a name before it can be saved")
            saved = profiles.save(profile)
            return {"profile": saved}, True

        if method == "delete":
            name = str(params.get("name", ""))
            if not profiles.delete(name):
                raise ValueError("No saved profile called %s" % name)
            if self.state.get("active_profile") == name:
                self.set_state(active_profile="")
            return {"deleted": name}, True

        if method == "preview":
            return self.start_preview(params), True

        if method == "commit":
            return (
                self.finish_preview(
                    str(params.get("transaction_id", "")), True, bool(params.get("save", False))
                ),
                True,
            )

        if method == "revert":
            return self.finish_preview(str(params.get("transaction_id", "")), False, False), True

        if method == "set_profile_auto":
            self.set_state(auto=bool(params.get("enabled", True)))
            if self.auto:
                self.auto_switch()
            return {"enabled": self.auto}, True

        if method == "manage":
            self.set_state(unmanaged=False)
            self.auto_switch()
            return {"unmanaged": False}, True

        if method == "unmanage":
            self.set_state(unmanaged=True)
            return {"unmanaged": True}, True

        raise ValueError("Unknown method %s" % method)

    def serve_client(self, client: socket.socket) -> None:
        buffer = b""
        try:
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    return
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if line.strip():
                        self.serve_request(client, line)
        except OSError:
            return
        finally:
            with self.lock:
                if client in self.clients:
                    self.clients.remove(client)
            client.close()

    def serve_request(self, client: socket.socket, line: bytes) -> None:
        try:
            request = json.loads(line)
        except ValueError:
            return
        reply = {
            "type": "response",
            "protocol_version": PROTOCOL_VERSION,
            "id": str(request.get("id", "")),
        }
        notify = False
        try:
            with self.lock:
                result, notify = self.handle(
                    str(request.get("method", "")), request.get("params") or {}, client
                )
            reply["result"] = result
        except Exception as error:  # surfaced to the panel as a readable message
            reply["error"] = {"message": str(error) or error.__class__.__name__}
        try:
            client.sendall((json.dumps(reply) + "\n").encode())
        except OSError:
            return
        if notify:
            self.broadcast()

    def watch_hyprland(self) -> None:
        """Re-evaluate profiles when displays come and go."""
        while True:
            try:
                for event, _payload in hypr.events():
                    if event in ("monitoraddedv2", "monitorremovedv2"):
                        with self.lock:
                            self.auto_switch()
                            self.refresh_monitors()
                        self.broadcast()
            except (OSError, RuntimeError):
                time.sleep(2)

    def watch_lid(self) -> None:
        """Re-evaluate profiles when logind reports the lid opening or closing."""
        logind = subprocess.Popen(
            ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1",
             "--object-path", "/org/freedesktop/login1"],
            stdout=subprocess.PIPE, text=True)
        for line in logind.stdout:
            if "'LidClosed'" not in line:
                continue
            log("lid state: %s" % ("closed" if hypr.lid_closed() else "open"))
            with self.lock:
                self.auto_switch()
            self.broadcast()

    def run(self) -> None:
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o600)
        server.listen(8)

        log("starting daemon")
        for target in (self.watch_hyprland, self.watch_lid):
            threading.Thread(target=target, daemon=True).start()
        log("lid state: %s" % ("closed" if hypr.lid_closed() else "open"))
        self.auto_switch()

        while True:
            client, _ = server.accept()
            threading.Thread(target=self.serve_client, args=(client,), daemon=True).start()


def set_process_name(name: str = "hyprmoncfgd") -> None:
    """Match on comm so `pgrep -x hyprmoncfgd` finds us behind the interpreter."""
    try:
        import ctypes

        ctypes.CDLL("libc.so.6", use_errno=True).prctl(
            15, ctypes.c_char_p(name.encode()), 0, 0, 0
        )
    except (OSError, AttributeError):
        pass


def main() -> int:
    set_process_name()
    Daemon().run()
    return 0
