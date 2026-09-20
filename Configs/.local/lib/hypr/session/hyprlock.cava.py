#!/usr/bin/env python3
"""Audio equaliser for a hyprlock label: hyprlock.cava.py HYPRLOCK_PID HEX [WIDTH PT FONT...].

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
BARS = 48
BLOCKS = "▁▂▃▄▅▆▇█"  # eight steps per row, so bars rise smoothly at ~17 repaints/sec
GRID = "█"
NOISE_REDUCTION = 88  # cava's filter, 0-100, default 77; higher is smoother, lazier


def measure(text, points, font):
    import gi
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    import cairo
    from gi.repository import Pango, PangoCairo
    layout = Pango.Layout.new(PangoCairo.create_context(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))))
    description = Pango.FontDescription.from_string(font)
    description.set_size(round(points * Pango.SCALE))
    layout.set_font_description(description)
    layout.set_text(text, -1)
    return layout.get_pixel_size()[0]


def bars_for(width, points, font):
    """As many bars as fit the label's container, each bar followed by a space."""
    bar, space = measure("█", points, font), measure(" ", points, font)
    return max(8, int((width + space) // (bar + space)))


def config(bars):
    return f"""[general]
bars = {bars}
framerate = 20
[output]
method = raw
channels = mono
mono_option = average
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = {LEVELS * len(BLOCKS)}
bar_delimiter = 59
frame_delimiter = 10
[smoothing]
noise_reduction = {NOISE_REDUCTION}
"""


def frame_markup(frame, hex6):
    heights = [int(value) for value in frame.split(b";") if value]
    if not any(heights):
        return ""
    on, off = f'<span foreground="#{hex6}">', f'<span foreground="#{hex6}" alpha="30%">'
    rows = []
    for level in range(LEVELS, 0, -1):
        floor = (level - 1) * len(BLOCKS)
        cells = [BLOCKS[min(len(BLOCKS), height - floor) - 1] if height > floor else None for height in heights]
        runs = itertools.groupby(cells, key=lambda cell: cell is not None)
        rows.append(" ".join(f"{on if lit else off}{' '.join(cell or GRID for cell in group)}</span>"
                             for lit, group in runs))
    return "\n".join(rows)


def release_inherited_fds():
    """hyprlock reads a label's pipe until EOF; its pipes are not close-on-exec."""
    for fd in os.listdir("/proc/self/fd"):
        if int(fd) > 2:
            try:
                os.close(int(fd))
            except OSError:
                pass


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
    out, settings = runtime / "hyprlock-cava.txt", runtime / "hyprlock-cava.conf"
    bars = bars_for(float(argv[2]), float(argv[3]), " ".join(argv[4:])) if len(argv) > 4 else BARS
    settings.write_text(config(bars))
    cava = subprocess.Popen(["cava", "-p", str(settings)], stdin=subprocess.DEVNULL,
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
        settings.unlink(missing_ok=True)


if __name__ == "__main__":
    release_inherited_fds()
    sys.exit(main(sys.argv[1:]))
