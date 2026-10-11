#!/usr/bin/env python3
import hashlib
import json
import sys
from pathlib import Path

from _common import (RENDER_OUTPUT_DIR, atomic_write, cache_hit, cache_store, hex_to_rgb, linear_to_srgb,
                     oklab_to_linear_rgb, palette_path, rgb_to_oklab, short_digest)

APP = "tempramp"
PALETTE = palette_path()
OUT = RENDER_OUTPUT_DIR / APP / "ramp.psv"

# Ordered outward from the neutral band. 45..59 stays uncoloured: that is the
# "nothing to report" span, and it is why each half starts one step off fg
# rather than at it.
HOT_TEMPERATURE_THRESHOLDS_C = [60, 65, 70, 75, 80, 85, 90]
COLD_TEMPERATURE_THRESHOLDS_C = [40, 35, 30, 25, 20, 0]
NEUTRAL_TEMPERATURE_C = 45


def oklab_to_hex(lab):
    return "#%02x%02x%02x" % tuple(
        max(0, min(255, round(linear_to_srgb(c) * 255))) for c in oklab_to_linear_rgb(*lab))


def interpolate_temperature_colors(thresholds, fg, anchor):
    # Interpolating in OkLab, not sRGB: a straight sRGB path between two hues
    # dips through a desaturated middle, which would flatten the mid bands.
    a, b = rgb_to_oklab(hex_to_rgb(fg)), rgb_to_oklab(hex_to_rgb(anchor))
    steps = len(thresholds)
    return {t: oklab_to_hex(tuple(a[k] + (b[k] - a[k]) * ((i + 1) / steps) for k in range(3)))
            for i, t in enumerate(thresholds)}


def has_hex_color_shape(value):
    return isinstance(value, str) and len(value) == 7 and value[0] == "#"


def main():
    if not PALETTE.is_file():
        sys.exit(f"render/{APP}: missing {PALETTE}")
    palette = json.loads(PALETTE.read_text())
    colors = palette.get("colors") or []
    fg, hot, cold = palette.get("fg"), colors[1] if len(colors) > 1 else None, \
        colors[4] if len(colors) > 4 else None
    if not all(has_hex_color_shape(color) for color in (fg, hot, cold)):
        sys.exit(f"render/{APP}: palette lacks fg, colors[1] or colors[4]")

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    hasher.update(Path(__file__).read_bytes())
    hasher.update(Path(__file__).with_name("_common.py").read_bytes())
    digest = short_digest(hasher)
    if cache_hit(APP, digest) and OUT.is_file():
        return

    # Each half runs from the theme's own text colour at the neutral band to the
    # palette's red (hot) or blue (cold) at the extreme, so the ends are colours
    # the theme already declares rather than a scale imposed on it.
    ramp = interpolate_temperature_colors(HOT_TEMPERATURE_THRESHOLDS_C, fg, hot)
    ramp.update(interpolate_temperature_colors(COLD_TEMPERATURE_THRESHOLDS_C, fg, cold))
    ramp[NEUTRAL_TEMPERATURE_C] = ""

    atomic_write(OUT, "".join(f"{t}|{ramp[t]}\n" for t in sorted(ramp, reverse=True)))
    cache_store(APP, digest)


if __name__ == "__main__":
    main()
