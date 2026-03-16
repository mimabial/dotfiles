#!/usr/bin/env python3

import json
import shutil
import subprocess
import sys


def _run(cmd):
    return subprocess.run(
        cmd,
        check=True,
        capture_output=True,
        text=True,
        timeout=2,
    ).stdout.strip()


def _status_error(message):
    return {
        "text": "?",
        "alt": "error",
        "tooltip": message,
        "class": "error",
    }


def _get_history_items():
    raw = _run(["dunstctl", "history"])
    payload = json.loads(raw)
    data = payload.get("data")
    if not isinstance(data, list) or not data:
        return []
    items = data[0]
    return items if isinstance(items, list) else []


def _get_count(kind):
    raw = _run(["dunstctl", "count", kind])
    return int(raw) if raw.isdigit() else 0


def _extract_field(item, key):
    value = item.get(key, {})
    if isinstance(value, dict):
        return str(value.get("data", "")).strip()
    return str(value).strip()


def get_dunst_status():
    if shutil.which("dunstctl") is None:
        return _status_error("dunstctl not found")

    try:
        history = _get_history_items()
        paused = _run(["dunstctl", "is-paused"]).strip().lower() == "true"
        displayed = _get_count("displayed")
        waiting = _get_count("waiting")
        history_count = _get_count("history")
    except (subprocess.SubprocessError, json.JSONDecodeError, ValueError):
        return _status_error("Failed to query dunst status")

    count = max(history_count, displayed + waiting, len(history))
    category_map = {
        "email": "email-notification",
        "chat": "chat-notification",
        "warning": "warning-notification",
        "error": "error-notification",
        "network": "network-notification",
        "battery": "battery-notification",
        "update": "update-notification",
        "music": "music-notification",
        "volume": "volume-notification",
    }

    alt = "none"
    if paused:
        alt = "dnd-notification" if count > 0 else "dnd-none"
    elif count > 0:
        alt = "notification"
        if history:
            category = _extract_field(history[0], "category").lower()
            alt = category_map.get(category, alt)

    tooltip_lines = [
        "Notifications",
        "scroll-down: show latest from history",
        "left-click: toggle do not disturb",
        "middle-click: open menu",
        "right-click: clear notifications",
    ]

    if history:
        tooltip_lines.append("")
        for item in history[:8]:
            summary = _extract_field(item, "summary")
            body = _extract_field(item, "body")
            line = summary or body or "Notification"
            if summary and body and body != summary:
                line = f"{summary}: {body}"
            tooltip_lines.append(f"• {line}")

    return {
        "text": "",
        "alt": alt,
        "tooltip": "\n".join(tooltip_lines),
        "class": alt,
    }


def main():
    status = get_dunst_status()
    sys.stdout.write(json.dumps(status) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
