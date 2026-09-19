"""Hyprland IPC: monitor state, live config application, and the event stream."""
from __future__ import annotations

import json
import os
import socket
import subprocess

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
SIGNATURE = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")


def _ipc_dir() -> str:
    return os.path.join(RUNTIME, "hypr", SIGNATURE)


def hyprctl(*args: str, timeout: float = 4.0) -> str:
    result = subprocess.run(
        ["hyprctl", *args], capture_output=True, text=True, timeout=timeout
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"hyprctl {' '.join(args)} failed")
    return result.stdout


def monitors() -> list[dict]:
    """Every monitor Hyprland knows about, disabled ones included."""
    return json.loads(hyprctl("monitors", "all", "-j"))


def apply_lua(code: str) -> None:
    """Hyprland rejects `hyprctl keyword` under the Lua parser; eval is the way in."""
    hyprctl("eval", code)


def reload() -> None:
    hyprctl("reload")


def output_key(make: str, model: str, name: str = "") -> str:
    """Profiles match on make|model so a display keeps its identity across ports."""
    make, model = (make or "").strip(), (model or "").strip()
    if make or model:
        return f"{make}|{model}".lower()
    return (name or "").lower()


def monitor_key(monitor: dict) -> str:
    return output_key(monitor.get("make", ""), monitor.get("model", ""), monitor.get("name", ""))


def mirror_source(monitor: dict, monitors: list[dict]) -> dict | None:
    """Hyprland reports the mirrored display by id, which is not stable enough to store."""
    return next((m for m in monitors if str(m.get("id")) == str(monitor.get("mirrorOf"))), None)


def mode_string(width: int, height: int, refresh: float) -> str:
    return f"{int(width)}x{int(height)}@{float(refresh):.2f}Hz"


def lid_state() -> str:
    """Empty when there is no lid at all, so desktops behave as always-open."""
    import glob

    for path in glob.glob("/proc/acpi/button/lid/*/state"):
        try:
            with open(path, encoding="utf-8") as handle:
                return "closed" if "closed" in handle.read().lower() else "open"
        except OSError:
            continue
    return ""


def lid_closed() -> bool:
    return lid_state() == "closed"


def is_internal(monitor: dict) -> bool:
    return str(monitor.get("name", "")).startswith(("eDP", "LVDS", "DSI"))


def events():
    """Yield (event, payload) from Hyprland's socket2 for as long as it stays up."""
    path = os.path.join(_ipc_dir(), ".socket2.sock")
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(path)
    buffer = b""
    try:
        while True:
            chunk = conn.recv(8192)
            if not chunk:
                return
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                text = line.decode("utf-8", "replace")
                name, _, payload = text.partition(">>")
                yield name, payload
    finally:
        conn.close()
