import math
import re
import subprocess
from pathlib import Path


def round_half_toward_positive_infinity(value):
    """JS Math.round rounds halves toward +inf; Python's round() is banker's."""
    return math.floor(value + 0.5)


def round_decimal_places(value, digits):
    scale = 10 ** digits
    return round_half_toward_positive_infinity(value * scale) / scale


def theme_override_slug(name):
    """Lua patterns are ASCII-only; looknfeel.lua theme_override_slugs identically so the TUI
    writes where the resolver reads."""
    out = re.sub(r"[^a-z0-9]+", "-", str(name or "default").lower())
    return out.strip("-")


def run_capture(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def read_text(path):
    try:
        return Path(path).read_text()
    except OSError:
        return ""
