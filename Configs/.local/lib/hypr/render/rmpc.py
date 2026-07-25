#!/usr/bin/env python3

import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store

STATE_HOME = Path(
    os.environ.get(
        "HYPR_STATE_HOME",
        str(Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hypr"),
    )
)
CACHE_HOME = Path(
    os.environ.get(
        "HYPR_CACHE_HOME",
        str(Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "hypr"),
    )
)
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
PALETTE = Path(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else STATE_HOME / "active-palette.json"
TEMPLATE_DIR = CONFIG_HOME / "wal" / "templates"
OUT_DIR = CACHE_HOME / "render" / "rmpc"
TEMPLATES = {
    "pywal16.ron": TEMPLATE_DIR / "colors-rmpc.ron",
    "pywal16-small.ron": TEMPLATE_DIR / "colors--small-rmpc.ron",
    "pywal16-big.ron": TEMPLATE_DIR / "colors--big-rmpc.ron",
}
APP = "rmpc"


def palette_mapping(palette):
    bg = palette.get("bg")
    fg = palette.get("fg")
    colors = palette.get("colors")
    if not isinstance(bg, str) or not isinstance(fg, str):
        raise ValueError("palette must contain string bg and fg values")
    if not isinstance(colors, list) or len(colors) < 16 or not all(
        isinstance(color, str) for color in colors[:16]
    ):
        raise ValueError("palette must contain at least 16 color strings")

    mapping = {"background": bg, "foreground": fg}
    mapping.update({f"color{i}": color for i, color in enumerate(colors[:16])})
    return mapping


def main():
    if not PALETTE.is_file():
        sys.exit(f"render/rmpc: missing {PALETTE}")

    missing = [str(path) for path in TEMPLATES.values() if not path.is_file()]
    if missing:
        sys.exit(f"render/rmpc: missing template: {', '.join(missing)}")

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    hasher.update(Path(__file__).read_bytes())
    for name, path in sorted(TEMPLATES.items()):
        hasher.update(name.encode())
        hasher.update(path.read_bytes())
    digest = hasher.hexdigest()[:16]

    if cache_hit(APP, digest) and all((OUT_DIR / name).is_file() for name in TEMPLATES):
        return

    try:
        mapping = palette_mapping(json.loads(PALETTE.read_text()))
        rendered = {
            name: path.read_text().format_map(mapping)
            for name, path in TEMPLATES.items()
        }
    except (json.JSONDecodeError, KeyError, ValueError) as error:
        sys.exit(f"render/rmpc: {error}")

    for name, content in rendered.items():
        atomic_write(OUT_DIR / name, content)
    cache_store(APP, digest)


if __name__ == "__main__":
    main()
