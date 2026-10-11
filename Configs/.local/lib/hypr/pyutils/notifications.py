#!/usr/bin/env python3

import os
import shutil
import threading
from subprocess import CalledProcessError, TimeoutExpired
from typing import Optional

from pyutils.child_process import run

DEFAULT_APP_NAME = "Hyprland"
DEFAULT_URGENCY = "normal"
SEND_TIMEOUT_SECONDS = 3


def _is_gui_available():
    return (
        os.environ.get("DISPLAY") is not None
        or os.environ.get("WAYLAND_DISPLAY") is not None
        or os.environ.get("XDG_SESSION_TYPE") == "wayland"
        or os.environ.get("XDG_SESSION_TYPE") == "x11"
    )


def _print_fallback(summary: str, body: Optional[str], app_name: Optional[str]):
    message = f"{summary}: {body}" if body else summary
    print(f"[{app_name or DEFAULT_APP_NAME}] {message}")


def build_dunstify_command(executable, summary, body, urgency, expire_milliseconds, icon, category, app_name, replace_id):
    command = [executable]
    for flag, value in (
        ("-u", urgency),
        ("-t", expire_milliseconds),
        ("-i", icon),
        ("-c", category),
        ("-a", app_name),
        ("-r", replace_id),
    ):
        if value is not None and value != "":
            command.extend([flag, str(value)])
    command.append(summary)
    if body:
        command.append(body)
    return command


def send_notification_async(
    summary: str,
    body: Optional[str] = None,
    urgency: Optional[str] = DEFAULT_URGENCY,
    expire_milliseconds: Optional[int] = None,
    icon: Optional[str] = None,
    category: Optional[str] = None,
    app_name: Optional[str] = DEFAULT_APP_NAME,
    replace_id: Optional[int] = None,
):
    dunstify_executable = shutil.which("dunstify") if _is_gui_available() else None
    if dunstify_executable is None:
        _print_fallback(summary, body, app_name)
        return

    command = build_dunstify_command(dunstify_executable, summary, body, urgency, expire_milliseconds, icon, category, app_name, replace_id)

    def send_dunstify_in_background():
        try:
            run(command, check=True, timeout=SEND_TIMEOUT_SECONDS, capture_output=True)
        except (CalledProcessError, TimeoutExpired, FileNotFoundError):
            _print_fallback(summary, body, app_name)

    threading.Thread(target=send_dunstify_in_background, daemon=True).start()
