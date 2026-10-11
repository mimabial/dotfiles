from __future__ import annotations

import configparser
import json
import os
import re
import shlex
from pathlib import Path
from urllib.parse import unquote, urlparse

from pyutils.xdg_base_dirs import xdg_config_home, xdg_data_home
from .processes import flatpak_launch_command, kitty_working_directory, process_commandline

EDITOR_WINDOW_CLASSES = {"code", "code-url-handler", "codium", "code - oss"}
EDITOR_TITLE_SUFFIXES = (" - Visual Studio Code", " - Code - OSS", " - VSCodium")
EDITOR_CONFIG_DIRECTORIES = ("Code", "Code - OSS", "VSCodium")
DESKTOP_FIELD_CODES = re.compile(r"\s+%[fFuUdDnNickvm]")
ELECTRON_HELPER_ARGS = ("--type=renderer", "--type=gpu-process", "--type=zygote", "--type=utility")


def clean_desktop_exec(value: str) -> str:
    return DESKTOP_FIELD_CODES.sub("", value).replace("%%", "%").strip()


def desktop_application_directories() -> list[Path]:
    data_home = xdg_data_home()
    dirs = [data_home / "applications"]
    for base in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if base:
            dirs.append(Path(base) / "applications")
    dirs.extend(
        [
            Path("/var/lib/flatpak/exports/share/applications"),
            data_home / "flatpak/exports/share/applications",
        ]
    )
    return dirs


def discover_desktop_commands() -> dict[str, str]:
    cache: dict[str, str] = {}
    for app_dir in reversed(desktop_application_directories()):
        if not app_dir.is_dir():
            continue
        for desktop in app_dir.glob("*.desktop"):
            parser = configparser.RawConfigParser(strict=False)
            try:
                parser.read(desktop, encoding="utf-8")
                if not parser.has_section("Desktop Entry"):
                    continue
                exec_value = parser.get("Desktop Entry", "Exec", fallback="")
                if not exec_value:
                    continue
                command = clean_desktop_exec(exec_value)
                keys = {desktop.stem.lower()}
                startup_class = parser.get("Desktop Entry", "StartupWMClass", fallback="")
                if startup_class:
                    keys.add(startup_class.lower())
                try:
                    parts = shlex.split(command)
                    if parts:
                        keys.add(Path(parts[0]).name.lower())
                except ValueError:
                    pass
                for key in keys:
                    cache[key] = command
            except (configparser.Error, OSError):
                continue
    return cache


def discover_window_launch(client: dict, exe: str, desktops: dict[str, str]) -> dict:
    pid = int(client.get("pid") or 0)
    initial_class = str(client.get("initialClass") or client.get("class") or "")
    cmdline = process_commandline(pid)
    flatpak = flatpak_launch_command(pid)
    desktop = None

    for key in (initial_class.lower(), str(client.get("class") or "").lower(), Path(exe).name.lower()):
        if key and key in desktops:
            desktop = desktops[key]
            break

    if flatpak:
        launch = flatpak
    elif desktop:
        launch = desktop
    elif cmdline and not any(arg in cmdline for arg in ELECTRON_HELPER_ARGS):
        launch = cmdline
    else:
        launch = exe

    return {
        "executable": exe,
        "process_command": cmdline,
        "flatpak_command": flatpak,
        "desktop_command": desktop,
        "command": launch,
    }


def editor_project_name(title: str) -> str | None:
    for marker in EDITOR_TITLE_SUFFIXES:
        idx = title.rfind(marker)
        if idx == -1:
            continue
        name = title[:idx].rsplit(" - ", 1)[-1].strip()
        return name or None
    return None


def discover_editor_projects() -> dict[str, str]:
    folders: dict[str, str] = {}
    for config_dir in EDITOR_CONFIG_DIRECTORIES:
        storage = xdg_config_home() / config_dir / "User/workspaceStorage"
        if not storage.is_dir():
            continue
        for workspace in storage.glob("*/workspace.json"):
            try:
                data = json.loads(workspace.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            uri = data.get("folder", "")
            if not uri.startswith("file://"):
                continue
            path = unquote(urlparse(uri).path)
            if Path(path).is_dir():
                folders.setdefault(Path(path).name, path)
                folders.setdefault(Path(path).name.lower(), path)
    return folders


def add_window_project(client: dict, folder_cache: dict[str, str]) -> None:
    pid = int(client.get("pid") or 0)
    initial_class = str(client.get("initialClass") or "").lower()
    if initial_class == "kitty":
        cwd = kitty_working_directory(pid)
        if cwd:
            client["launch"]["working_directory"] = cwd
        return
    if initial_class in EDITOR_WINDOW_CLASSES:
        project = editor_project_name(str(client.get("title") or ""))
        if not project:
            return
        client["launch"]["project_name"] = project
        folder = folder_cache.get(project) or folder_cache.get(project.lower())
        if folder:
            client["launch"]["project_directory"] = folder


def window_launch_command(client: dict) -> str | None:
    initial_class = str(client.get("initialClass") or "").lower()
    command = client["launch"].get("command")
    if not command:
        return None
    if initial_class == "kitty" and client["launch"].get("working_directory") and Path(client["launch"]["working_directory"]).is_dir():
        return f"{command} --directory {shlex.quote(client['launch']['working_directory'])}"
    if initial_class in EDITOR_WINDOW_CLASSES and client["launch"].get("project_directory") and Path(client["launch"]["project_directory"]).is_dir():
        return f"{command} {shlex.quote(client['launch']['project_directory'])}"
    return command

