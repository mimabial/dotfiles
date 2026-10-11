#!/usr/bin/env python3
"""Shrinks the text with a Pango size span until it fits, and below MIN_SCALE
truncates it with an ellipsis instead. A keep/shrink decision holds for any text
of the same shape, so it goes to SHAPE_CACHE; a truncation is text-specific and
goes to TEXT_CACHE.
"""
import functools
import math
import sys
from pathlib import Path
from typing import NamedTuple

MIN_SCALE = 0.75
SCALE_STEP = 0.01
NBSP = "\u00a0"


class FitDecision(NamedTuple):
    action: str
    padding_spaces: int = 0
    pango_size: int = 0
    escape_markup: bool = False
    fitted_text: str = ""


class PangoResources(NamedTuple):
    glib: object
    pango: object
    context: object


@functools.cache
def pango_resources():
    import gi
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    import cairo
    from gi.repository import GLib, Pango, PangoCairo
    context = PangoCairo.create_context(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)))
    return PangoResources(GLib, Pango, context)


def is_valid_markup(text):
    resources = pango_resources()
    try:
        resources.pango.parse_markup(text, -1, "\0")
        return True
    except resources.glib.Error:
        return False


def text_layout(markup, size, font):
    resources = pango_resources()
    layout = resources.pango.Layout.new(resources.context)
    description = resources.pango.FontDescription.from_string(font)
    description.set_size(round(size * resources.pango.SCALE))
    layout.set_font_description(description)
    if is_valid_markup(markup):
        layout.set_markup(markup, -1)
    else:
        layout.set_text(markup, -1)
    return layout


def measure_text(markup, size, font):
    return text_layout(markup, size, font).get_pixel_size()


def overhang_padding(markup, size, font):
    """Non-breaking spaces widening the advance, which hyprlock sizes the label from."""
    resources = pango_resources()
    ink, logical = text_layout(markup, size, font).get_extents()
    overflow = (ink.x + ink.width - logical.width) / resources.pango.SCALE
    return math.ceil(overflow / measure_text(NBSP, size, font)[0]) if overflow > 0 else 0


def text_fits_frame(markup, width, height, size, font):
    w, h = measure_text(markup, size, font)
    return w <= width and h <= height


def choose_fit(text, width, height, size, font):
    resources = pango_resources()
    if text_fits_frame(text, width, height, size, font):
        pad = overhang_padding(text, size, font)
        return FitDecision("pad", padding_spaces=pad) if pad and text_fits_frame(NBSP * pad + text + NBSP * pad, width, height, size, font) else FitDecision("keep")
    escape = not is_valid_markup(text)
    body = resources.glib.markup_escape_text(text, -1) if escape else text
    w, h = measure_text(body, size, font)
    scale = min(width / w, height / h)
    while scale >= MIN_SCALE:
        span = int(size * scale * resources.pango.SCALE)
        if text_fits_frame(f'<span size="{span}">{body}</span>', width, height, size, font):
            return FitDecision("size", pango_size=span, escape_markup=escape)
        scale -= SCALE_STEP
    minimum = round(size * MIN_SCALE * resources.pango.SCALE)
    plain = resources.pango.parse_markup(body, -1, "\0")[2]
    span = f'<span size="{minimum}">'
    low, high = 0, len(plain)
    while low < high:
        mid = (low + high + 1) // 2
        candidate = f"{span}{resources.glib.markup_escape_text(plain[:mid].rstrip(), -1)}…</span>"
        low, high = (mid, high) if text_fits_frame(candidate, width, height, size, font) else (low, mid - 1)
    if low == 0:  # not even one character fits; overflowing beats an ellipsis alone
        return FitDecision("size", pango_size=minimum, escape_markup=escape)
    return FitDecision("text", fitted_text=f"{span}{resources.glib.markup_escape_text(plain[:low].rstrip(), -1)}…</span>")


def render_fit(text, decision):
    if decision.action == "keep":
        return text
    if decision.action == "pad":
        return NBSP * decision.padding_spaces + text + NBSP * decision.padding_spaces
    if decision.action == "text":
        return decision.fitted_text
    resources = pango_resources()
    return f'<span size="{decision.pango_size}">{resources.glib.markup_escape_text(text, -1) if decision.escape_markup else text}</span>'


def fit(text, width, height, size, font):
    return render_fit(text, choose_fit(text, width, height, size, font))


def main(argv):
    shape_cache, text_cache = Path(argv[0]), Path(argv[1])
    width, height, size, font = float(argv[2]), float(argv[3]), float(argv[4]), " ".join(argv[5:])
    text = sys.stdin.read().strip(" \n\r\t")
    decision = choose_fit(text, width, height, size, font)
    target = text_cache if decision.action == "text" else shape_cache
    target.parent.mkdir(parents=True, exist_ok=True)
    if decision.action == "text":
        text_cache.write_text(decision.fitted_text)
    else:
        value = decision.padding_spaces if decision.action == "pad" else decision.pango_size
        cached = decision.action if decision.action == "keep" else f"{decision.action} {value} {int(decision.escape_markup)}"
        shape_cache.write_text(cached + "\n")
    print(render_fit(text, decision))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
