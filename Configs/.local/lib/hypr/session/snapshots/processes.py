from __future__ import annotations

import configparser
import os
import shlex
from pathlib import Path


def process_commandline(pid: int) -> str | None:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes().rstrip(b"\0")
    except OSError:
        return None
    if not raw:
        return None
    return " ".join(shlex.quote(part.decode(errors="replace")) for part in raw.split(b"\0") if part)


def process_executable(pid: int) -> str | None:
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return None
    return None if exe.endswith(" (deleted)") else exe


def flatpak_launch_command(pid: int) -> str | None:
    info = Path(f"/proc/{pid}/root/.flatpak-info")
    if not info.is_file():
        return None
    parser = configparser.RawConfigParser()
    try:
        parser.read(info, encoding="utf-8")
        app_id = parser.get("Application", "name", fallback="").strip()
    except (configparser.Error, OSError):
        return None
    return f"flatpak run {shlex.quote(app_id)}" if app_id else None


def process_children(pid: int) -> list[int]:
    children: list[int] = []
    task_dir = Path(f"/proc/{pid}/task")
    try:
        tids = list(task_dir.iterdir())
    except OSError:
        return children
    for tid in tids:
        try:
            children.extend(int(value) for value in (tid / "children").read_text().split())
        except (OSError, ValueError):
            continue
    return children


def kitty_working_directory(pid: int) -> str | None:
    for child in process_children(pid):
        try:
            first_arg = Path(f"/proc/{child}/cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
        except OSError:
            continue
        if Path(first_arg).name == "kitten":
            continue
        try:
            cwd = os.readlink(f"/proc/{child}/cwd")
        except OSError:
            continue
        if cwd and Path(cwd).is_dir():
            return cwd
    return None

