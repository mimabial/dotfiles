#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess


DEFAULT_TIMEOUT_MS = 4000
DEFAULT_URGENCY = "normal"
DUNST_APP_NAME = "Codex"


def _text(value: object) -> str:
    return value if isinstance(value, str) else ""


def _looks_like_codex(cmd: object) -> bool:
    title = _text(getattr(cmd, "title", ""))
    body = _text(getattr(cmd, "body", ""))
    app = _text(getattr(cmd, "application_name", ""))
    notification_types = tuple(getattr(cmd, "notification_types", ()) or ())
    type_text = "\n".join(item for item in notification_types if isinstance(item, str))
    haystack = "\n".join((title, body, app, type_text)).lower()

    return (
        "codex" in haystack
        or title.lower().startswith("approval requested:")
        or body.lower().startswith("codex wants to ")
    )


def _timeout_ms(cmd: object) -> int:
    timeout = getattr(cmd, "timeout", -1)
    if isinstance(timeout, int) and timeout > 0:
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


def _stack_tag(cmd: object) -> str:
    title = _text(getattr(cmd, "title", "")).lower()
    body = _text(getattr(cmd, "body", "")).lower()
    if title.startswith("approval requested:") or body.startswith("codex wants to "):
        return "codex-approval"
    return "codex"


def main(cmd: object) -> bool:
    if not _looks_like_codex(cmd):
        return False

    dunstify = shutil.which("dunstify")
    if not dunstify:
        return False

    title = _text(getattr(cmd, "title", "")).strip()
    body = _text(getattr(cmd, "body", "")).strip()
    if not title:
        return False

    command = [
        dunstify,
        "-a",
        DUNST_APP_NAME,
        "-u",
        _urgency(cmd),
        "-t",
        str(_timeout_ms(cmd)),
        "-h",
        f"string:x-dunst-stack-tag:{_stack_tag(cmd)}",
    ]

    icon_path = _text(getattr(cmd, "icon_path", "")).strip()
    if icon_path:
        command.extend(("-i", icon_path))

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
