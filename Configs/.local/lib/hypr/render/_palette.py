#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

from _common import ANSI_COLOR_COUNT, CACHE_HOME, atomic_write, short_digest

DEFAULT_OUT = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "hypr" / "active-palette.json"
THEME_ROOT  = Path(os.environ.get("HYPR_CONFIG_HOME", str(Path.home() / ".config" / "hypr"))) / "themes"
MATUGEN_CONFIG = Path(__file__).with_name("matugen.toml")
MATUGEN_CACHE = CACHE_HOME / "matugen-schemes"
MOST_DOMINANT_SOURCE = "0"

HUE_ROLES = ("red", "green", "yellow", "blue", "magenta", "cyan")
ANSI_ROLES = {
    "dark":  ("surface", *HUE_ROLES, "on_surface",
              "surface_variant", *(f"on_{hue}_container" for hue in HUE_ROLES), "on_surface_variant"),
    "light": ("surface", *HUE_ROLES, "on_surface",
              "surface_variant", *HUE_ROLES, "on_surface_variant"),
}

HEX = re.compile(r"#[0-9a-fA-F]{6}")
KEY_VALUE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+(\S+)\s*$")

def is_light_color(hex_value: str) -> bool:
    if not HEX.fullmatch(hex_value or ""):
        return False
    r = int(hex_value[1:3], 16)
    g = int(hex_value[3:5], 16)
    b = int(hex_value[5:7], 16)
    return ((0.299 * r + 0.587 * g + 0.114 * b) / 255) > 0.5

def parse_kitty_theme(path: Path) -> dict:
    data = {"bg": None, "fg": None, "cursor": None, "cursor_text": None,
            "selection_fg": None, "selection_bg": None, "colors": [None] * ANSI_COLOR_COUNT}
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
            if 0 <= idx < ANSI_COLOR_COUNT:
                data["colors"][idx] = v
    return data

def parse_palette_toml(path: Path) -> dict:
    with path.open("rb") as f:
        raw = tomllib.load(f)
    return {
        "bg":     raw.get("background"),
        "fg":     raw.get("foreground"),
        "cursor": raw.get("cursor-color") or raw.get("cursor"),  # "cursor" predates "cursor-color"
        "cursor_text":  raw.get("cursor-text"),
        "selection_fg": raw.get("selection-foreground"),
        "selection_bg": raw.get("selection-background"),
        "colors": (raw.get("colors") or []) + [None] * ANSI_COLOR_COUNT,
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

    parsed["colors"] = parsed["colors"][:ANSI_COLOR_COUNT]
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

    roles = matugen_roles(img)
    role = lambda name: roles[name][variant]["color"]
    return {
        "source": f"wallpaper:{img}",
        "mode":   "wallpaper",
        "background": variant,
        "bg":     role("surface"),
        "fg":     role("on_surface"),
        "colors": [role(name) for name in ANSI_ROLES[variant]],
        "cursor": role("on_surface"),
        "cursor_text":  role("surface"),
        "selection_fg": role("on_secondary_container"),
        "selection_bg": role("secondary_container"),
    }

def matugen_roles(img: Path) -> dict:
    matugen = shutil.which("matugen") or sys.exit("_palette: matugen not installed")
    hasher = hashlib.sha256(MATUGEN_CONFIG.read_bytes())
    for path in (Path(matugen), img):
        stat = path.stat()
        hasher.update(f"{path}\0{stat.st_size}\0{stat.st_mtime_ns}\0".encode())
    cache = MATUGEN_CACHE / f"{short_digest(hasher)}.json"
    if cache.is_file():
        return json.loads(cache.read_text())
    try:
        scheme = subprocess.run([matugen, "image", str(img), "--config", str(MATUGEN_CONFIG), "--dry-run", "--quiet",
                                 "--json", "hex", "--source-color-index", MOST_DOMINANT_SOURCE],
                                check=True, capture_output=True, text=True).stdout
    except subprocess.CalledProcessError as error:
        sys.exit(f"_palette: matugen failed: {error.stderr.strip()}")
    roles = json.loads(scheme)["colors"]
    atomic_write(cache, json.dumps(roles) + "\n")
    return roles

def main():
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--theme", metavar="PACK")
    source.add_argument("--wallpaper", metavar="PATH")
    parser.add_argument("--variant", choices=("dark", "light"), default=os.environ.get("HYPR_COLOR_VARIANT", "dark"))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    args = parser.parse_args()

    if args.theme:
        payload = resolve_theme(args.theme)
    else:
        payload = resolve_wallpaper(args.wallpaper, args.variant)

    atomic_write(Path(args.out), json.dumps(payload, indent=2) + "\n")
    print(f"_palette: wrote {args.out} ({payload['source']})", file=sys.stderr)

if __name__ == "__main__":
    main()
