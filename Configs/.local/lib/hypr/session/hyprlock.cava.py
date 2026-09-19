#!/usr/bin/env python3
"""Audio equaliser for a hyprlock label: hyprlock.cava.py HYPRLOCK_PID HEX.

Started once by the lock screen; writes each cava frame as Pango markup to
$XDG_RUNTIME_DIR/hypr/hyprlock-cava.txt, which a label cats, until hyprlock exits.
"""
import itertools
import os
import select
import subprocess
import sys
from pathlib import Path

LEVELS = 9
CONFIG = f"""[general]
bars = 48
framerate = 20
[output]
method = raw
channels = mono
mono_option = average
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = {LEVELS}
bar_delimiter = 59
frame_delimiter = 10
"""


def frame_markup(frame, hex6):
    heights = [int(value) for value in frame.split(b";") if value]
    if not any(heights):
        return ""
    on, off = f'<span foreground="#{hex6}">', f'<span foreground="#{hex6}" alpha="30%">'
    rows = []
    for level in range(LEVELS, 0, -1):
        runs = itertools.groupby(height >= level for height in heights)
        rows.append(" ".join(f"{on if lit else off}{' '.join('█' * len(list(cells)))}</span>" for lit, cells in runs))
    return "\n".join(rows)


def main(argv):
    try:
        pid = int(argv[0])
        # The explorer's preview runs this command too; only a real lock screen gets bars.
        if Path(f"/proc/{pid}/comm").read_text().strip() != "hyprlock":
            return 0
        pidfd = os.pidfd_open(pid)
    except (OSError, ValueError, IndexError):
        return 0
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hypr"
    runtime.mkdir(parents=True, exist_ok=True)
    out, config = runtime / "hyprlock-cava.txt", runtime / "hyprlock-cava.conf"
    config.write_text(CONFIG)
    cava = subprocess.Popen(["cava", "-p", str(config)], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    poller = select.poll()
    poller.register(pidfd, select.POLLIN)
    poller.register(cava.stdout, select.POLLIN)
    pending = b""
    try:
        while True:
            for fd, _ in poller.poll():
                if fd == pidfd:
                    return 0
                chunk = os.read(fd, 65536)
                if not chunk:
                    return 0
                *frames, pending = (pending + chunk).split(b"\n")
                if frames:
                    staging = out.with_suffix(".tmp")
                    staging.write_text(frame_markup(frames[-1], argv[1]))
                    os.replace(staging, out)
    finally:
        cava.terminate()
        cava.wait()
        out.unlink(missing_ok=True)
        config.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
