#!/usr/bin/env python3
# coding: utf-8

import os
import shutil
import threading
from subprocess import CalledProcessError, TimeoutExpired, run
from typing import Optional

DEFAULT_APP_NAME = "Hyprland"
DEFAULT_URGENCY = "normal"


def _is_gui_available():
    """Check if a GUI environment is available."""
    return (
        os.environ.get("DISPLAY") is not None
        or os.environ.get("WAYLAND_DISPLAY") is not None
        or os.environ.get("XDG_SESSION_TYPE") == "wayland"
        or os.environ.get("XDG_SESSION_TYPE") == "x11"
    )


def _has_dunstify():
    """Check if dunstify is available."""
    return shutil.which("dunstify") is not None


def _print_fallback(summary: str, body: Optional[str], app_name: Optional[str]):
    """Print a human-readable fallback message to stdout."""
    prefix = f"[{app_name or DEFAULT_APP_NAME}]"
    message = f"{summary}"
    if body:
        message += f": {body}"
    print(f"{prefix} {message}")


def send(
    summary: str,
    body: Optional[str] = None,
    urgency: Optional[str] = DEFAULT_URGENCY,
    expire_time: Optional[int] = None,
    icon: Optional[str] = None,
    category: Optional[str] = None,
    app_name: Optional[str] = DEFAULT_APP_NAME,
    replace_id: Optional[int] = None,
    transient: bool = False,
    sync_tag: Optional[str] = None,
):
    """Send a notification using dunstify.

    Parameters
    ----------
    summary : str
        The summary of the notification.
    body : Optional[str]
        The body of the notification.
    urgency : Optional[str]
        The urgency level (low, normal, critical).
    expire_time : Optional[int]
        The timeout in milliseconds at which to expire the notification.
    icon : Optional[str]
        The icon filename or stock icon to display.
    category : Optional[str]
        The notification category.
    app_name : Optional[str]
        The app name for the notification.
    replace_id : Optional[int]
        The ID of the notification to replace.
    transient : bool
        Compatibility flag for callers that want short-lived notifications.
    sync_tag : Optional[str]
        Stack/replacement tag for daemons that honor the
        x-canonical-private-synchronous hint.
    """
    # Fall back to stdout when desktop notifications are unavailable.
    if not _is_gui_available() or not _has_dunstify():
        _print_fallback(summary, body, app_name)
        return

    command = [shutil.which("dunstify") or "dunstify"]

    if urgency:
        command.extend(["-u", urgency])
    if expire_time:
        command.extend(["-t", str(expire_time)])
    if icon:
        command.extend(["-i", icon])
    if category:
        command.extend(["-c", category])
    if app_name:
        command.extend(["-a", app_name])
    if replace_id:
        command.extend(["-r", str(replace_id)])
    if sync_tag:
        command.extend(["-h", f"string:x-canonical-private-synchronous:{sync_tag}"])

    command.append(summary)
    if body:
        command.append(body)

    def _send_in_background():
        """Send notification in background thread."""
        try:
            run(command, check=True, timeout=3, capture_output=True)
        except (CalledProcessError, TimeoutExpired, FileNotFoundError):
            _print_fallback(summary, body, app_name)
            return

    # Run in daemon thread so it doesn't block main thread
    thread = threading.Thread(target=_send_in_background, daemon=True)
    thread.start()


# Example usage
if __name__ == "__main__":
    send("Test Notification", "This is a test notification body.", urgency="normal")
