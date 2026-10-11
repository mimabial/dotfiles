from __future__ import annotations

import math
import sys
import time
from pathlib import Path

from pyutils.hyprctl import batch_json
from .applications import EDITOR_WINDOW_CLASSES, add_window_project, discover_desktop_commands, discover_editor_projects, discover_window_launch, editor_project_name
from .processes import process_executable
from .storage import write_snapshot


EXCLUDED_EXECUTABLES = {
    "Hyprland",
    "hyprland",
    "Xwayland",
    "xdg-desktop-portal",
    "xdg-desktop-portal-hyprland",
    "xdg-desktop-portal-gtk",
    "xdg-desktop-portal-kde",
    "xdg-desktop-portal-wlr",
    "xdg-document-portal",
    "xdg-permission-store",
    "dbus-daemon",
    "dbus-broker",
    "ags",
    "eww",
    "dunst",
    "mako",
    "fnott",
    "swww-daemon",
    "swww",
    "hyprpaper",
    "mpvpaper",
    "awww-daemon",
    "hyprlock",
    "hypridle",
    "hyprsunset",
    "wl-paste",
    "wl-copy",
    "cliphist",
    "polkit-kde-authentication-agent-1",
    "polkit-gnome-authentication-agent-1",
    "lxqt-policykit-agent",
    "pipewire",
    "pipewire-pulse",
    "wireplumber",
}

def focus_recency(client: dict) -> float:
    rank = client.get("focusHistoryID")
    return rank if isinstance(rank, int) and rank >= 0 else math.inf


def save_session(name: str, verbose: bool) -> None:
    clients, workspaces, monitors = batch_json("clients", "workspaces", "monitors")
    desktops = discover_desktop_commands()
    folders = discover_editor_projects()

    swallowed = {c.get("swallowing") for c in clients if c.get("swallowing") not in (None, "", "0x0")}
    seen_pids: set[int] = set()
    seen_multi: set[tuple[int, int, str]] = set()
    by_recency: list[dict] = []
    skipped: list[str] = []

    for client in sorted(clients, key=lambda c: (bool(c.get("hidden")), focus_recency(c))):
        addr = client.get("address")
        pid = int(client.get("pid") or 0)
        initial_class = str(client.get("initialClass") or "")
        if addr in swallowed:
            skipped.append(f"swallowed {initial_class} {addr}")
            continue
        if pid <= 0:
            skipped.append(f"no-pid {initial_class}")
            continue
        exe = process_executable(pid)
        if not exe:
            skipped.append(f"no-exe pid={pid} {initial_class}")
            continue
        if Path(exe).name in EXCLUDED_EXECUTABLES:
            continue

        if initial_class.lower() in EDITOR_WINDOW_CLASSES:
            project = editor_project_name(str(client.get("title") or "")) or str(client.get("title") or "")
            key = (pid, int((client.get("workspace") or {}).get("id") or 0), project)
            if key in seen_multi:
                continue
            seen_multi.add(key)
        else:
            if pid in seen_pids:
                continue
            seen_pids.add(pid)

        item = dict(client)
        item["launch"] = discover_window_launch(item, exe, desktops)
        add_window_project(item, folders)
        by_recency.append(item)

    launch_order = by_recency[::-1]
    snapshot = {
        "version": 1,
        "saved_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "monitors": monitors,
        "workspaces": workspaces,
        "clients": launch_order,
    }
    path = write_snapshot(name, snapshot)
    print(f"saved {len(by_recency)} windows to {path}")
    if verbose:
        for message in skipped:
            print(f"skip: {message}", file=sys.stderr)

