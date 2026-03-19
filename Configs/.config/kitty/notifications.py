#!/usr/bin/env python3

from __future__ import annotations

import os
import shutil
import subprocess


DEFAULT_TIMEOUT_MS = 4000
DEFAULT_URGENCY = "normal"
DUNST_APP_NAMES = {"codex": "Codex", "claude": "Claude Code"}
DEFAULT_ICON_CANDIDATES = (
    "/usr/lib/kitty/logo/kitty.png",
    "/usr/share/icons/hicolor/256x256/apps/kitty.png",
)


def _text(value: object) -> str:
    return value if isinstance(value, str) else ""


def _detect_app(cmd: object) -> str | None:
    """Return a key from DUNST_APP_NAMES if the notification matches, else None."""
    title = _text(getattr(cmd, "title", ""))
    body = _text(getattr(cmd, "body", ""))
    app = _text(getattr(cmd, "application_name", ""))
    notification_types = tuple(getattr(cmd, "notification_types", ()) or ())
    type_text = "\n".join(item for item in notification_types if isinstance(item, str))
    haystack = "\n".join((title, body, app, type_text)).lower()

    if (
        "codex" in haystack
        or title.lower().startswith("approval requested:")
        or body.lower().startswith("codex wants to ")
    ):
        return "codex"
    if "claude" in haystack:
        return "claude"
    return None


def _timeout_ms(cmd: object) -> int:
    timeout = getattr(cmd, "timeout", -1)
    if isinstance(timeout, int) and timeout > 0:
        # Cap at 30 seconds - larger values are likely unit errors
        if timeout > 30000:
            return DEFAULT_TIMEOUT_MS
        return timeout
    return DEFAULT_TIMEOUT_MS


def _urgency(cmd: object) -> str:
    urgency = getattr(cmd, "urgency", None)
    if urgency is None:
        return DEFAULT_URGENCY

    name = getattr(urgency, "name", "")
    if isinstance(name, str) and name:
        return name.lower()

    return {
        0: "low",
        1: "normal",
        2: "critical",
    }.get(getattr(urgency, "value", None), DEFAULT_URGENCY)


def _stack_tag(cmd: object, app_key: str) -> str:
    title = _text(getattr(cmd, "title", "")).lower()
    body = _text(getattr(cmd, "body", "")).lower()
    if title.startswith("approval requested:") or body.startswith("codex wants to "):
        return "codex-approval"
    return app_key


def _normalized_content(cmd: object) -> tuple[str, str]:
    title = _text(getattr(cmd, "title", "")).strip()
    body = _text(getattr(cmd, "body", "")).strip()

    lower_title = title.lower()
    if lower_title.startswith("approval requested:"):
        remainder = title.split(":", 1)[1].strip()
        title = "Approval requested"
        if remainder and not body:
            body = remainder
    elif lower_title.startswith("codex wants to "):
        remainder = title[len("Codex wants to ") :].strip()
        title = "Codex wants to"
        if remainder and not body:
            body = remainder
    elif not body and "\n" in title:
        first_line, remainder = title.split("\n", 1)
        title = first_line.strip()
        body = remainder.strip()

    return title, body


def _icon_args(cmd: object) -> list[str]:
    icon_path = _text(getattr(cmd, "icon_path", "")).strip()
    if not icon_path:
        for candidate in DEFAULT_ICON_CANDIDATES:
            if os.path.isfile(candidate):
                icon_path = candidate
                break

    if not icon_path:
        return []
    if os.path.isfile(icon_path):
        return ["-I", icon_path]
    return ["-i", icon_path]


def main(cmd: object) -> bool:
    app_key = _detect_app(cmd)
    if app_key is None:
        return False

    dunstify = shutil.which("dunstify")
    if not dunstify:
        return False

    title, body = _normalized_content(cmd)
    if not title:
        return False

    command = [
        dunstify,
        "-a",
        DUNST_APP_NAMES[app_key],
        "-u",
        _urgency(cmd),
        "-t",
        str(_timeout_ms(cmd)),
        "-h",
        f"string:x-dunst-stack-tag:{_stack_tag(cmd, app_key)}",
    ]

    command.extend(_icon_args(cmd))

    command.append(title)
    if body:
        command.append(body)

    try:
        subprocess.run(
            command,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except Exception:
        return False

    return True
