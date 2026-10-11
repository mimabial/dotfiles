from __future__ import annotations

import json
import os
import socket

from pyutils import child_process
from pyutils.xdg_base_dirs import xdg_runtime_dir

RUNTIME = str(xdg_runtime_dir() or "/run/user/%d" % os.getuid())
SIGNATURE = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")


def _ipc_dir() -> str:
    return os.path.join(RUNTIME, "hypr", SIGNATURE)


def hyprctl(*args: str, timeout: float = 4.0) -> str:
    result = child_process.run(
        ["hyprctl", *args], capture_output=True, text=True, timeout=timeout
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"hyprctl {' '.join(args)} failed")
    return result.stdout


def monitors() -> list[dict]:
    """Disabled ones included."""
    return json.loads(hyprctl("monitors", "all", "-j"))


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


def lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def exec_command(command: str) -> None:
    hyprctl("dispatch", f"hl.dsp.exec_cmd({lua_string(command)})")


def connect_events() -> socket.socket:
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        conn.connect(os.path.join(_ipc_dir(), ".socket2.sock"))
    except OSError:
        conn.close()
        raise
    return conn


def read_events(conn: socket.socket):
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
