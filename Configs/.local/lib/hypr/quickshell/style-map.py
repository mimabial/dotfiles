#!/usr/bin/env python

"""Emit the css-key hierarchy of each quickshell bar layout."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from style_map.layouts import QUICKSHELL_CONFIG_DIR
from style_map.output import render_layout_style_map
from style_map.qml import index_qml_components

from pyutils.xdg_base_dirs import xdg_cache_home

STYLE_MAP_CACHE_DIR = xdg_cache_home() / "hypr/quickshell/style-map"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("layouts", nargs="*", help="layouts to emit (default: all)")
    parser.add_argument("-o", "--out", default=str(STYLE_MAP_CACHE_DIR), help="output directory")
    parser.add_argument("--stdout", action="store_true", help="print instead of writing files")
    args = parser.parse_args()

    index = index_qml_components(QUICKSHELL_CONFIG_DIR)
    names = args.layouts or sorted(p.stem for p in (QUICKSHELL_CONFIG_DIR / "layouts").glob("*.json"))
    out = Path(args.out)
    if not args.stdout:
        out.mkdir(parents=True, exist_ok=True)
    for layout in names:
        try:
            body = render_layout_style_map(layout, index)
        except Exception as error:  # a half-saved json must not kill the watcher
            print(f"style-map: {layout}: {error}", file=sys.stderr)
            continue
        if args.stdout:
            print(body)
        else:
            (out / f"{layout}.md").write_text(body, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
