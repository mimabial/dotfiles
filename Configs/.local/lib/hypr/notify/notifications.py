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


def get_swaync_status():
    if shutil.which("swaync-client") is None:
        return _status_error("swaync-client not found")

    # Primary path: let swaync render waybar-compatible JSON.
    try:
        raw = _run(["swaync-client", "-swb"])
        data = json.loads(raw)
        if isinstance(data, dict):
            data.setdefault("text", "0")
            data.setdefault("alt", "none")
            data.setdefault("tooltip", "Notifications")
            data.setdefault("class", data.get("alt", "none"))
            return data
    except (subprocess.SubprocessError, json.JSONDecodeError):
        pass

    # Fallback path: derive minimal status from count + DND.
    try:
        count_raw = _run(["swaync-client", "-c"])
        dnd_raw = _run(["swaync-client", "-D"]).lower()
        count = int(count_raw) if count_raw.isdigit() else 0
        dnd = dnd_raw == "true"
    except (subprocess.SubprocessError, ValueError):
        return _status_error("Failed to query swaync status")

    if dnd:
        alt = "dnd-notification" if count > 0 else "dnd-none"
        tooltip = f"Do Not Disturb: ON\\nNotifications waiting: {count}"
    else:
        alt = "notification" if count > 0 else "none"
        tooltip = f"Do Not Disturb: OFF\\nNotifications: {count}"

    return {
        "text": str(count),
        "alt": alt,
        "tooltip": tooltip,
        "class": alt,
    }


def main():
    status = get_swaync_status()
    sys.stdout.write(json.dumps(status) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
