#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils import child_process

DUNSTCTL_TIMEOUT_SECONDS = 2


def toggle_dnd():
    child_process.run(
        ["dunstctl", "set-paused", "toggle"],
        check=True,
        capture_output=True,
        timeout=DUNSTCTL_TIMEOUT_SECONDS,
    )


def main():
    if sys.argv[1:] != ["--toggle"]:
        sys.exit("usage: notifications.py --toggle")
    toggle_dnd()


if __name__ == "__main__":
    main()
