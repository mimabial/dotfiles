#!/usr/bin/env python3
"""Pango text measurements for the rofi geometry helpers.

One entry point for the three measurements rofi/lib/fonts.bash needs, so the
gi/Pango import is paid once per measurement instead of once per heredoc.
Every mode reads the font from FONT_DESC and exits 1 when it cannot measure,
which is what the bash callers treat as "fall back to the estimate".
"""

import os
import sys

try:
    import gi

    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
    import cairo
except Exception:
    sys.exit(1)


def pango_context():
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
    return PangoCairo.create_context(cairo.Context(surface))


def layout_for(description):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
    layout = PangoCairo.create_layout(cairo.Context(surface))
    layout.set_font_description(description)
    return layout


def mode_height(description):
    context = pango_context()
    context.set_font_description(description)
    metrics = context.get_metrics(description, Pango.Language.get_default())
    # rofi's em is the line height, which includes the line gap; ascent+descent
    # undercounts it (Miracode 15: 21px vs rofi's 22px) and clips the last row.
    height = metrics.get_height() / Pango.SCALE
    if height <= 0:
        height = (metrics.get_ascent() + metrics.get_descent()) / Pango.SCALE
    if height <= 0:
        sys.exit(1)
    print(f"{height:.2f}")


def mode_extents(description):
    layout = layout_for(description)
    width = 0
    height = 0
    for row in sys.stdin.read().splitlines():
        layout.set_text(row, -1)
        row_width, row_height = layout.get_pixel_size()
        width = max(width, row_width)
        height = max(height, row_height)
    if width <= 0 or height <= 0:
        sys.exit(1)
    print(width, height)


def mode_align(description):
    glyph = os.environ.get("GLYPH", "")
    if not glyph:
        sys.exit(1)

    layout = layout_for(description)

    def width(text):
        layout.set_text(text, -1)
        return layout.get_pixel_size()[0]

    rows = []
    for line in sys.stdin.read().splitlines():
        flag, _, label = line.partition("\t")
        rows.append((flag == "1", label))

    space = width(" ")
    if not rows or space <= 0:
        sys.exit(1)

    glyph_width = width(glyph)
    # two spaces of breathing room past the widest label, when the rows themselves
    # are what the column is measured from
    edge = max(width(label) for _, label in rows) + 2 * space + glyph_width
    # Reaching a wider target costs whole spaces, and the division floors twice
    # over: a target landing mid-space would round labels of differing length to
    # columns one space apart, and a row as wide as the column rofi hands it is
    # elided -- taking the glyph with it.
    target = int(os.environ.get("TARGET_PX", "0") or 0)
    edge += max(0, (target - edge) // space) * space

    for flagged, label in rows:
        if not flagged:
            print(label)
            continue
        print(label + " " * max(1, round((edge - glyph_width - width(label)) / space)) + glyph)


MODES = {"height": mode_height, "extents": mode_extents, "align": mode_align}


def main():
    mode = MODES.get(sys.argv[1] if len(sys.argv) > 1 else "")
    if mode is None:
        print(f"usage: {os.path.basename(sys.argv[0])} {{{'|'.join(MODES)}}}", file=sys.stderr)
        return 2

    font_desc = os.environ.get("FONT_DESC", "").strip()
    if not font_desc:
        return 1

    mode(Pango.FontDescription.from_string(font_desc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
