#!/usr/bin/env python3
import json
import sys
from pathlib import Path

from _common import CONFIG_HOME, atomic_write, cache_hit, cache_store, palette_path
from _roles import qt_roles_from_palette, qt_role_inputs_digest

from _kvantum import resolve_kvantum_color_files

APP = "hyprtoolkit"
PALETTE = palette_path()
OUT_FILE = CONFIG_HOME / "hyprtoolkit.conf"


def opaque_argb(color):
    return "0xff" + color.removeprefix("#")


def render(roles):
    colors = {
        "background": roles.window_surface,
        "base": roles.button_surface,
        "alternate_base": roles.alternate_surface,
        "text": roles.text,
        "bright_text": roles.highlight_text,
        "link_text": roles.link,
        "accent": roles.accent,
        "accent_secondary": roles.hover,
    }
    return "".join(f"{key} = {opaque_argb(color)}\n" for key, color in colors.items())


def main():
    if not PALETTE.is_file():
        sys.exit(f"render/{APP}: missing {PALETTE}")

    palette = json.loads(PALETTE.read_text())
    kvantum_files = resolve_kvantum_color_files(palette)
    digest = qt_role_inputs_digest(PALETTE, kvantum_files, Path(__file__))
    if cache_hit(APP, digest) and OUT_FILE.exists():
        return

    atomic_write(OUT_FILE, render(qt_roles_from_palette(palette, kvantum_files)))
    cache_store(APP, digest)


if __name__ == "__main__":
    main()
