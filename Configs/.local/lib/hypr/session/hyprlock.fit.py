#!/usr/bin/env python3
"""Pango side of hyprlock.fit.sh: hyprlock.fit.py SHAPE_CACHE TEXT_CACHE WIDTH HEIGHT SIZE FONT... < text

Shrinks the text with a Pango size span until it fits, and below MIN_SCALE
truncates it with an ellipsis instead. A keep/shrink decision holds for any text
of the same shape, so it goes to SHAPE_CACHE; a truncation is text-specific and
goes to TEXT_CACHE.
"""
import functools
import math
import sys
from pathlib import Path

MIN_SCALE = 0.75
NBSP = "\u00a0"


@functools.cache
def pango():
    import gi
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    import cairo
    from gi.repository import GLib, Pango, PangoCairo
    context = PangoCairo.create_context(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)))
    return GLib, Pango, context


def valid_markup(text):
    GLib, Pango, _ = pango()
    try:
        Pango.parse_markup(text, -1, "\0")
        return True
    except GLib.Error:
        return False


def layout_for(markup, size, font):
    _, Pango, context = pango()
    layout = Pango.Layout.new(context)
    description = Pango.FontDescription.from_string(font)
    description.set_size(round(size * Pango.SCALE))
    layout.set_font_description(description)
    if valid_markup(markup):
        layout.set_markup(markup, -1)
    else:
        layout.set_text(markup, -1)
    return layout


def measure(markup, size, font):
    return layout_for(markup, size, font).get_pixel_size()


def padding(markup, size, font):
    """Non-breaking spaces widening the advance, which hyprlock sizes the label from."""
    _, Pango, _ = pango()
    ink, logical = layout_for(markup, size, font).get_extents()
    overflow = (ink.x + ink.width - logical.width) / Pango.SCALE
    return math.ceil(overflow / measure(NBSP, size, font)[0]) if overflow > 0 else 0


def fits(markup, width, height, size, font):
    w, h = measure(markup, size, font)
    return w <= width and h <= height


def plan(text, width, height, size, font):
    """("keep",), ("pad", n, 0), ("size", pango_size, escape) or ("text", markup)."""
    GLib, Pango, _ = pango()
    if fits(text, width, height, size, font):
        pad = padding(text, size, font)
        return ("pad", pad, 0) if pad and fits(NBSP * pad + text + NBSP * pad, width, height, size, font) else ("keep",)
    escape = not valid_markup(text)
    body = GLib.markup_escape_text(text, -1) if escape else text
    w, h = measure(body, size, font)
    scale = min(width / w, height / h)
    while scale >= MIN_SCALE:
        span = int(size * scale * 1024)
        if fits(f'<span size="{span}">{body}</span>', width, height, size, font):
            return ("size", span, escape)
        scale -= 0.01
    minimum = round(size * MIN_SCALE * 1024)
    plain = Pango.parse_markup(body, -1, "\0")[2]
    span = f'<span size="{minimum}">'
    low, high = 0, len(plain)
    while low < high:
        mid = (low + high + 1) // 2
        candidate = f"{span}{GLib.markup_escape_text(plain[:mid].rstrip(), -1)}…</span>"
        low, high = (mid, high) if fits(candidate, width, height, size, font) else (low, mid - 1)
    if low == 0:  # not even one character fits; overflowing beats an ellipsis alone
        return ("size", minimum, escape)
    return ("text", f"{span}{GLib.markup_escape_text(plain[:low].rstrip(), -1)}…</span>")


def render(text, decision):
    if decision[0] == "keep":
        return text
    if decision[0] == "pad":
        return NBSP * decision[1] + text + NBSP * decision[1]
    if decision[0] == "text":
        return decision[1]
    GLib, _, _ = pango()
    return f'<span size="{decision[1]}">{GLib.markup_escape_text(text, -1) if decision[2] else text}</span>'


def fit(text, width, height, size, font):
    return render(text, plan(text, width, height, size, font))


def main(argv):
    shape_cache, text_cache = Path(argv[0]), Path(argv[1])
    width, height, size, font = float(argv[2]), float(argv[3]), float(argv[4]), " ".join(argv[5:])
    text = sys.stdin.read().strip(" \n\r\t")
    decision = plan(text, width, height, size, font)
    target = text_cache if decision[0] == "text" else shape_cache
    target.parent.mkdir(parents=True, exist_ok=True)
    if decision[0] == "text":
        text_cache.write_text(decision[1])
    else:
        shape_cache.write_text(" ".join(str(int(v)) if isinstance(v, bool) else str(v) for v in decision) + "\n")
    print(render(text, decision))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
