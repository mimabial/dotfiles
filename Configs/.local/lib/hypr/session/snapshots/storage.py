from __future__ import annotations

import json
import os
from pathlib import Path

from pyutils.xdg_base_dirs import xdg_state_home

SNAPSHOT_DIRECTORY = Path(os.environ.get("HYPR_STATE_HOME") or xdg_state_home() / "hypr") / "sessions"
NO_SESSIONS_MESSAGE = "no saved sessions"
LAUNCH_FIELDS = {
    "executable": "_exe", "process_command": "_cmdline", "flatpak_command": "_flatpak",
    "desktop_command": "_desktop", "command": "_launch", "working_directory": "_p_cwd",
    "project_name": "_p_project", "project_directory": "_p_folder",
}


def snapshot_path(name: str) -> Path:
    clean = name.strip() or "default"
    if "/" in clean or clean in {".", ".."}:
        raise SystemExit(f"invalid session name: {name}")
    return SNAPSHOT_DIRECTORY / f"{clean}.json"


def read_snapshot(name: str) -> dict:
    path = snapshot_path(name)
    if not path.is_file():
        raise SystemExit(f"session not found: {name}")
    snapshot = json.loads(path.read_text())
    for client in snapshot.get("clients") or []:
        client["launch"] = {field: client.pop(legacy) for field, legacy in LAUNCH_FIELDS.items() if legacy in client}
    return snapshot


def write_snapshot(name: str, snapshot: dict) -> Path:
    stored = dict(snapshot)
    stored["clients"] = []
    for client in snapshot["clients"]:
        item = dict(client)
        launch = item.pop("launch")
        item.update({legacy: launch[field] for field, legacy in LAUNCH_FIELDS.items() if field in launch})
        stored["clients"].append(item)
    path = snapshot_path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(stored, indent=2) + "\n")
    temporary.replace(path)
    return path


def list_sessions() -> None:
    names = sorted(path.stem for path in SNAPSHOT_DIRECTORY.glob("*.json"))
    print("\n".join(names) if names else NO_SESSIONS_MESSAGE)


def delete_session(name: str) -> None:
    path = snapshot_path(name)
    if not path.exists():
        raise SystemExit(f"session not found: {name}")
    path.unlink()
    print(f"deleted {name}")

