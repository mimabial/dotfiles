from __future__ import annotations

import configparser
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from pyutils.xdg_base_dirs import xdg_data_dirs, xdg_data_home

from .bounded_io import BoundedOutputError, read_limited_text, run_bounded_process
from .records import MAX_IDENTIFIER_CHARS


BROWSER_QUERY_TIMEOUT_SECONDS = 2
MAX_DESKTOP_FILE_BYTES = 256 * 1024
MAX_APPLICATION_ENTRIES = 10_000
MAX_BROWSERS = 256
MAX_BROWSER_NAME_CHARS = 512
MAX_BROWSER_ICON_CHARS = 1024
MAX_PATH_CHARS = 4096
MAX_DEFAULT_BROWSER_OUTPUT_BYTES = 16 * 1024


def xdg_application_dirs() -> list[Path]:
    candidates = [xdg_data_home() / "applications", Path.home() / ".nix-profile/share/applications"]
    candidates.extend(path / "applications" for path in xdg_data_dirs())
    result: list[Path] = []
    seen: set[Path] = set()
    for path in candidates:
        if path not in seen:
            seen.add(path)
            result.append(path)
    return result


def default_browser_desktop_id() -> str:
    environment = {**os.environ, "LC_ALL": "C"}
    environment.pop("BROWSER", None)
    for command in (
        ["xdg-settings", "get", "default-web-browser"],
        ["xdg-mime", "query", "default", "x-scheme-handler/https"],
    ):
        try:
            process = run_bounded_process(
                command,
                max_output_bytes=MAX_DEFAULT_BROWSER_OUTPUT_BYTES,
                timeout_seconds=BROWSER_QUERY_TIMEOUT_SECONDS,
                env=environment,
            )
            result = process.stdout.decode("utf-8").strip()
        except (
            OSError,
            UnicodeDecodeError,
            BoundedOutputError,
            subprocess.TimeoutExpired,
        ):
            continue
        if result:
            identifier = Path(result).name
            return identifier if len(identifier) <= MAX_IDENTIFIER_CHARS else ""
    return ""


def read_browser_desktop_entry(path: Path) -> dict[str, Any] | None:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        raw = read_limited_text(path, MAX_DESKTOP_FILE_BYTES, "Desktop entry")
        parser.read_string(raw, source=str(path))
        entry = parser["Desktop Entry"]
    except (OSError, UnicodeError, ValueError, configparser.Error, KeyError):
        return None
    if entry.get("Type", "Application") != "Application":
        return None
    if entry.get("Hidden", "false").lower() == "true":
        return None
    if entry.get("NoDisplay", "false").lower() == "true":
        return None
    mime_types = {value for value in entry.get("MimeType", "").split(";") if value}
    if "x-scheme-handler/https" not in mime_types:
        return None
    try_exec = entry.get("TryExec", "").strip()
    if try_exec:
        executable = try_exec if os.path.isabs(try_exec) else shutil.which(try_exec)
        if not executable or not os.access(executable, os.X_OK):
            return None
    name = entry.get("Name", "").strip()
    icon = entry.get("Icon", "").strip()
    identifier = path.name
    try:
        desktop_path = str(path.resolve())
    except (OSError, RuntimeError):
        return None
    if (
        not name
        or len(name) > MAX_BROWSER_NAME_CHARS
        or len(icon) > MAX_BROWSER_ICON_CHARS
        or len(identifier) > MAX_IDENTIFIER_CHARS
        or len(desktop_path) > MAX_PATH_CHARS
    ):
        return None
    return {
        "id": identifier,
        "name": name,
        "icon": icon,
        "desktopPath": desktop_path,
    }


def discover_browsers(
    application_dirs: list[Path] | None = None,
    default_desktop: str | None = None,
) -> dict[str, Any]:
    directories = application_dirs if application_dirs is not None else xdg_application_dirs()
    default_id = (
        default_browser_desktop_id()
        if default_desktop is None
        else Path(default_desktop).name
    )
    if len(default_id) > MAX_IDENTIFIER_CHARS:
        default_id = ""
    browsers: list[dict[str, Any]] = []
    seen: set[str] = set()
    scanned = 0
    exhausted = False
    for directory in directories:
        if not directory.is_dir():
            continue
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    scanned += 1
                    if scanned > MAX_APPLICATION_ENTRIES:
                        exhausted = True
                        break
                    if not entry.name.endswith(".desktop") or entry.name in seen:
                        continue
                    seen.add(entry.name)
                    try:
                        if not entry.is_file(follow_symlinks=True):
                            continue
                    except OSError:
                        continue
                    path = Path(entry.path)
                    browser = read_browser_desktop_entry(path)
                    if browser is None:
                        continue
                    browser["isDefault"] = path.name == default_id
                    browsers.append(browser)
                    if len(browsers) >= MAX_BROWSERS:
                        exhausted = True
                        break
        except OSError:
            continue
        if exhausted:
            break
    browsers.sort(key=lambda item: (not item["isDefault"], item["name"].casefold(), item["id"]))
    return {"ok": True, "browsers": browsers, "defaultDesktop": default_id}
