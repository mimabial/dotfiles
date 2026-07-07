#!/usr/bin/env python3
"""Generate or extend rofi picker character databases."""

from __future__ import annotations

import argparse
import json
import sys
import unicodedata
import urllib.request
from pathlib import Path


NERD_FONTS_GLYPHNAMES_URL = (
    "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json"
)

BOXDRAW_RANGES: tuple[tuple[str, int, int], ...] = (
    ("box drawing", 0x2500, 0x257F),
    ("block elements", 0x2580, 0x259F),
    ("geometric shapes", 0x25A0, 0x25FF),
    ("braille patterns", 0x2800, 0x28FF),
    ("symbols for legacy computing", 0x1FB00, 0x1FBFF),
)


def read_rows(path: Path) -> list[tuple[str, str]]:
    if not path.exists():
        return []

    rows: list[tuple[str, str]] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line:
            continue
        if "\t" not in line:
            raise ValueError(f"{path}:{line_no}: expected tab-separated row")
        char, label = line.split("\t", 1)
        if not char:
            raise ValueError(f"{path}:{line_no}: empty character field")
        rows.append((char, label.strip()))
    return rows


def unicode_label(char: str) -> str:
    name = unicodedata.name(char)
    for prefix in ("BOX DRAWINGS ",):
        if name.startswith(prefix):
            name = name[len(prefix) :]
            break
    return name.lower()


def assigned_chars(start: int, end: int) -> list[str]:
    chars: list[str] = []
    for codepoint in range(start, end + 1):
        char = chr(codepoint)
        if unicodedata.category(char) == "Cn":
            continue
        chars.append(char)
    return chars


def write_rows(path: Path, rows: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_name(f".{path.name}.tmp")
    body = "".join(f"{char}\t{label}\n" for char, label in rows)
    tmp_path.write_text(body, encoding="utf-8")
    tmp_path.replace(path)


def read_text_source(source: str) -> str:
    if source.startswith(("http://", "https://")):
        with urllib.request.urlopen(source, timeout=30) as response:
            return response.read().decode("utf-8")
    return Path(source).read_text(encoding="utf-8")


def glyph_rows(source: str) -> tuple[list[tuple[str, str]], str]:
    data = json.loads(read_text_source(source))
    metadata = data.get("METADATA", {})
    version = str(metadata.get("version", "unknown"))
    rows: list[tuple[str, str]] = []

    for name, payload in data.items():
        if name == "METADATA":
            continue
        if not isinstance(payload, dict):
            raise ValueError(f"{name}: expected glyph metadata object")
        char = payload.get("char")
        if not isinstance(char, str) or not char:
            raise ValueError(f"{name}: missing glyph character")
        rows.append((char, name))

    return rows, version


def generate_glyph(path: Path, source: str) -> tuple[int, int, str]:
    old_rows = set(read_rows(path))
    rows, version = glyph_rows(source)
    new_rows = set(rows)
    write_rows(path, rows)
    return len(old_rows - new_rows), len(new_rows - old_rows), version


def extend_boxdraw(path: Path) -> int:
    rows = read_rows(path)
    seen = {char for char, _label in rows}
    added = 0

    for _range_name, start, end in BOXDRAW_RANGES:
        for char in assigned_chars(start, end):
            if char in seen:
                continue
            rows.append((char, unicode_label(char)))
            seen.add(char)
            added += 1

    write_rows(path, rows)
    return added


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--hypr-dir",
        type=Path,
        default=Path.home() / ".config" / "hypr",
        help="directory containing picker DB files",
    )
    parser.add_argument(
        "--boxdraw",
        action="store_true",
        help="extend boxdraw.db from Unicode drawing/symbol blocks",
    )
    parser.add_argument(
        "--glyph",
        action="store_true",
        help="regenerate glyph.db from Nerd Fonts glyphnames.json",
    )
    parser.add_argument(
        "--glyph-source",
        default=NERD_FONTS_GLYPHNAMES_URL,
        help="Nerd Fonts glyphnames.json path or URL",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not args.boxdraw and not args.glyph:
        print("Nothing selected. Use --boxdraw and/or --glyph.", file=sys.stderr)
        return 2

    if args.boxdraw:
        added = extend_boxdraw(args.hypr_dir / "boxdraw.db")
        print(f"boxdraw.db: added {added} entries")

    if args.glyph:
        removed, added, version = generate_glyph(
            args.hypr_dir / "glyph.db",
            args.glyph_source,
        )
        print(f"glyph.db: Nerd Fonts {version}, removed {removed}, added {added}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
