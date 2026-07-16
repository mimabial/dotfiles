#!/usr/bin/env python3
# _palette.py
#   --theme <pack-name>       theme mode: derive palette from pack's kitty.theme
#   --wallpaper <image-path>  wallpaper mode: invoke pywal16, read its colors.json
#   --variant dark|light      wallpaper color variant
#   --out <path>              output JSON path (default: ~/.local/state/hypr/active-palette.json)
#
# Writes the active palette as JSON; atomic move into place.

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

DEFAULT_OUT = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "hypr" / "active-palette.json"
WAL_CACHE   = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "wal" / "colors.json"
THEME_ROOT  = Path(os.environ.get("HYPR_CONFIG_HOME", str(Path.home() / ".config" / "hypr"))) / "themes"

HEX = re.compile(r"#[0-9a-fA-F]{6}")
KEY_VALUE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+(\S+)\s*$")

def is_light_color(hex_value: str) -> bool:
    if not HEX.fullmatch(hex_value or ""):
        return False
    r = int(hex_value[1:3], 16)
    g = int(hex_value[3:5], 16)
    b = int(hex_value[5:7], 16)
    return ((0.299 * r + 0.587 * g + 0.114 * b) / 255) > 0.5

PYWAL_DEFAULTS = {
    "dark":  {"BACKEND": "colorthief", "CONTRAST": "3.0", "SATURATE": "0.4", "COLS16": "lighten"},
    "light": {"BACKEND": "colorthief", "CONTRAST": "3.0", "SATURATE": "0.6", "COLS16": "darken"},
}

def pywal_setting(name: str, variant: str) -> str:
    return (os.environ.get(f"PYWAL_{variant.upper()}_{name}")
            or os.environ.get(f"PYWAL_{name}")
            or PYWAL_DEFAULTS[variant].get(name, ""))

def parse_kitty_theme(path: Path) -> dict:
    """Parse a kitty.theme into {bg, fg, cursor?, cursor_text?, selection_fg?,
    selection_bg?, colors[0..15]}."""
    data = {"bg": None, "fg": None, "cursor": None, "cursor_text": None,
            "selection_fg": None, "selection_bg": None, "colors": [None] * 16}
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip() if raw.lstrip().startswith("#") else raw
        m = KEY_VALUE.match(line)
        if not m:
            continue
        k, v = m.group(1), m.group(2)
        if not HEX.fullmatch(v):
            continue
        if k == "background":
            data["bg"] = v
        elif k == "foreground":
            data["fg"] = v
        elif k == "cursor":
            data["cursor"] = v
        elif k == "cursor_text_color":
            data["cursor_text"] = v
        elif k == "selection_foreground":
            data["selection_fg"] = v
        elif k == "selection_background":
            data["selection_bg"] = v
        elif k.startswith("color"):
            try:
                idx = int(k[5:])
            except ValueError:
                continue
            if 0 <= idx < 16:
                data["colors"][idx] = v
    return data

def parse_palette_toml(path: Path) -> dict:
    """Parse palette.toml: {background, foreground, cursor-color?, cursor-text?,
    selection-foreground?, selection-background?, colors[0..15]}."""
    with path.open("rb") as f:
        raw = tomllib.load(f)
    return {
        "bg":     raw.get("background"),
        "fg":     raw.get("foreground"),
        "cursor": raw.get("cursor-color") or raw.get("cursor"),  # "cursor" predates "cursor-color"
        "cursor_text":  raw.get("cursor-text"),
        "selection_fg": raw.get("selection-foreground"),
        "selection_bg": raw.get("selection-background"),
        "colors": (raw.get("colors") or [None] * 16) + [None] * 16,  # pad short lists
    }

def resolve_theme(pack_name: str) -> dict:
    pack_dir = THEME_ROOT / pack_name
    toml_file = pack_dir / "palette.toml"
    kitty = pack_dir / "kitty.theme"

    if toml_file.is_file():
        parsed = parse_palette_toml(toml_file)
        source = toml_file
    elif kitty.is_file():
        parsed = parse_kitty_theme(kitty)
        source = kitty
    else:
        sys.exit(f"_palette: no palette.toml or kitty.theme in {pack_dir}")

    parsed["colors"] = parsed["colors"][:16]
    missing = []
    if not parsed["bg"]: missing.append("background")
    if not parsed["fg"]: missing.append("foreground")
    for i, c in enumerate(parsed["colors"]):
        if not c: missing.append(f"color{i}")
    if missing:
        sys.exit(f"_palette: {source} missing: {', '.join(missing)}")
    out = {
        "source": f"theme:{pack_name}",
        "mode":   "theme",
        "background": "light" if is_light_color(parsed["bg"]) else "dark",
        "bg":     parsed["bg"],
        "fg":     parsed["fg"],
        "colors": parsed["colors"],
    }
    for key in ("cursor", "cursor_text", "selection_fg", "selection_bg"):
        if parsed.get(key):
            out[key] = parsed[key]
    return out

def resolve_wallpaper(image_path: str, variant: str) -> dict:
    img = Path(image_path).expanduser().resolve()
    if not img.is_file():
        sys.exit(f"_palette: wallpaper not found: {img}")

    backend = pywal_setting("BACKEND", variant)
    contrast = pywal_setting("CONTRAST", variant)
    saturate = pywal_setting("SATURATE", variant)
    cols16 = pywal_setting("COLS16", variant)

    wal_cmd = ["wal", "-q", "-n", "-s", "-t", "-e", "-i", str(img)]
    if variant == "light":
        wal_cmd.append("-l")
    if backend:
        wal_cmd += ["--backend", backend]
    if contrast:
        wal_cmd += ["--contrast", contrast]
    if saturate:
        wal_cmd += ["--saturate", saturate]
    if cols16:
        wal_cmd += ["--cols16", cols16]

    # Defer extraction to pywal16; it writes WAL_CACHE.
    try:
        subprocess.run(wal_cmd, check=True)
    except FileNotFoundError:
        sys.exit("_palette: pywal (wal) not installed")
    except subprocess.CalledProcessError as e:
        sys.exit(f"_palette: pywal failed: {e}")
    if not WAL_CACHE.is_file():
        sys.exit(f"_palette: pywal did not produce {WAL_CACHE}")
    d = json.loads(WAL_CACHE.read_text())
    colors = d.get("colors", {})
    out = {
        "source": f"wallpaper:{img}",
        "mode":   "wallpaper",
        "background": variant,
        "bg":     d["special"]["background"],
        "fg":     d["special"]["foreground"],
        "colors": [colors[f"color{i}"] for i in range(16)],
    }
    if d["special"].get("cursor"):
        out["cursor"] = d["special"]["cursor"]
    return out

def atomic_write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(payload, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except FileNotFoundError: pass
        raise

def resolve_from_wal_cache(variant: str) -> dict:
    if not WAL_CACHE.is_file():
        sys.exit(f"_palette: no wal cache at {WAL_CACHE}")
    d = json.loads(WAL_CACHE.read_text())
    colors = d.get("colors", {})
    img = d.get("wallpaper") or ""
    if img == "None":
        img = ""
    out = {
        "source": f"wallpaper:{img}" if img else "wallpaper:",
        "mode":   "wallpaper",
        "background": variant,
        "bg":     d["special"]["background"],
        "fg":     d["special"]["foreground"],
        "colors": [colors[f"color{i}"] for i in range(16)],
    }
    if d["special"].get("cursor"):
        out["cursor"] = d["special"]["cursor"]
    return out

def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--theme", metavar="PACK")
    g.add_argument("--wallpaper", metavar="PATH")
    g.add_argument("--from-wal-cache", action="store_true",
                   help="reshape existing ~/.cache/wal/colors.json instead of re-running pywal")
    ap.add_argument("--variant", choices=("dark", "light"), default=os.environ.get("HYPR_COLOR_VARIANT", "dark"))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()

    if args.theme:
        payload = resolve_theme(args.theme)
    elif args.from_wal_cache:
        payload = resolve_from_wal_cache(args.variant)
    else:
        payload = resolve_wallpaper(args.wallpaper, args.variant)

    atomic_write_json(Path(args.out), payload)
    print(f"_palette: wrote {args.out} ({payload['source']})", file=sys.stderr)

if __name__ == "__main__":
    main()
