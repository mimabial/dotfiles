#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store
from _roles import palette_roles, roles_digest

from _shell import shell_files

APP = "hyprtoolkit"
PALETTE = Path(
    sys.argv[1]
    if len(sys.argv) > 1 and sys.argv[1]
    else os.environ.get("HYPR_STATE_HOME", os.path.expanduser("~/.local/state/hypr"))
    + "/active-palette.json"
)
OUT_FILE = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "hypr" / "hyprtoolkit.conf"


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
    shell_kvconfig, shell_colors_map = shell_files(palette)
    digest = roles_digest(PALETTE, shell_kvconfig, shell_colors_map, Path(__file__))
    if cache_hit(APP, digest) and OUT_FILE.exists():
        return

    atomic_write(OUT_FILE, render(palette_roles(palette, shell_kvconfig, shell_colors_map)))
    cache_store(APP, digest)


if __name__ == "__main__":
    main()
