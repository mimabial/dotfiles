#!/usr/bin/env python3
# Renderer: temperature -> colour ramp for the sysinfo widgets.
# Emits the thresholds sysinfo/lib/temp-color.bash and sysinfo/sensorsinfo.py
# read, so the ramp follows the palette instead of a hardcoded scale.

import hashlib
import json
import math
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store

APP = "tempramp"
PALETTE = Path(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
               os.environ.get("HYPR_STATE_HOME",
                              os.path.expanduser("~/.local/state/hypr")) + "/active-palette.json")
OUT = Path(os.environ.get("HYPR_CACHE_HOME",
                          os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")) + "/hypr")) \
      / "render" / APP / "ramp.psv"

# Ordered outward from the neutral band. 45..59 stays uncoloured: that is the
# "nothing to report" span, and it is why each half starts one step off fg
# rather than at it.
HOT = [60, 65, 70, 75, 80, 85, 90]
COLD = [40, 35, 30, 25, 20, 0]
NEUTRAL = 45


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def to_oklab(hex_value):
    r, g, b = (_srgb_to_linear(int(hex_value[i:i + 2], 16) / 255) for i in (1, 3, 5))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = math.cbrt(l), math.cbrt(m), math.cbrt(s)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


def to_hex(lab):
    L, a, b = lab
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    channels = (+4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    return "#%02x%02x%02x" % tuple(
        max(0, min(255, round(_linear_to_srgb(c) * 255))) for c in channels)


def half(thresholds, fg, anchor):
    # Interpolating in OkLab, not sRGB: a straight sRGB path between two hues
    # dips through a desaturated middle, which would flatten the mid bands.
    a, b = to_oklab(fg), to_oklab(anchor)
    steps = len(thresholds)
    return {t: to_hex(tuple(a[k] + (b[k] - a[k]) * ((i + 1) / steps) for k in range(3)))
            for i, t in enumerate(thresholds)}


def is_hex(value):
    return isinstance(value, str) and len(value) == 7 and value[0] == "#"


def main():
    if not PALETTE.is_file():
        sys.exit(f"render/{APP}: missing {PALETTE}")
    palette = json.loads(PALETTE.read_text())
    colors = palette.get("colors") or []
    fg, hot, cold = palette.get("fg"), colors[1] if len(colors) > 1 else None, \
        colors[4] if len(colors) > 4 else None
    if not all(is_hex(c) for c in (fg, hot, cold)):
        sys.exit(f"render/{APP}: palette lacks fg, colors[1] or colors[4]")

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    hasher.update(Path(__file__).read_bytes())
    h = hasher.hexdigest()[:16]
    if cache_hit(APP, h) and OUT.is_file():
        return

    # Each half runs from the theme's own text colour at the neutral band to the
    # palette's red (hot) or blue (cold) at the extreme, so the ends are colours
    # the theme already declares rather than a scale imposed on it.
    ramp = half(HOT, fg, hot)
    ramp.update(half(COLD, fg, cold))
    ramp[NEUTRAL] = ""

    atomic_write(OUT, "".join(f"{t}|{ramp[t]}\n" for t in sorted(ramp, reverse=True)))
    cache_store(APP, h)


if __name__ == "__main__":
    main()
