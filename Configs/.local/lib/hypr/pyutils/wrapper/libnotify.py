#!/usr/bin/env python3

import os
import shutil
import threading
from subprocess import CalledProcessError, TimeoutExpired, run
from typing import Optional

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


def _has_dunstify():
    return shutil.which("dunstify") is not None


def _print_fallback(summary: str, body: Optional[str], app_name: Optional[str]):
    prefix = f"[{app_name or DEFAULT_APP_NAME}]"
    message = f"{summary}"
    if body:
        message += f": {body}"
    print(f"{prefix} {message}")


def dunstify_command(summary, body, urgency, expire_time, icon, category, app_name, replace_id):
    command = [shutil.which("dunstify") or "dunstify"]
    for flag, value in (
        ("-u", urgency),
        ("-t", expire_time),
        ("-i", icon),
        ("-c", category),
        ("-a", app_name),
        ("-r", replace_id),
    ):
        if value:
            command.extend([flag, str(value)])
    command.append(summary)
    if body:
        command.append(body)
    return command


def send(
    summary: str,
    body: Optional[str] = None,
    urgency: Optional[str] = DEFAULT_URGENCY,
    expire_time: Optional[int] = None,
    icon: Optional[str] = None,
    category: Optional[str] = None,
    app_name: Optional[str] = DEFAULT_APP_NAME,
    replace_id: Optional[int] = None,
):
    if not _is_gui_available() or not _has_dunstify():
        _print_fallback(summary, body, app_name)
        return

    command = dunstify_command(summary, body, urgency, expire_time, icon, category, app_name, replace_id)

    def _send_in_background():
        try:
            run(command, check=True, timeout=SEND_TIMEOUT_SECONDS, capture_output=True)
        except (CalledProcessError, TimeoutExpired, FileNotFoundError):
            _print_fallback(summary, body, app_name)

    threading.Thread(target=_send_in_background, daemon=True).start()


if __name__ == "__main__":
    send("Test Notification", "This is a test notification body.", urgency="normal")
