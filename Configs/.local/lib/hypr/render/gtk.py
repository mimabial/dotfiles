#!/usr/bin/env python3
# Renderer: Pywal16-Gtk theme (gtk-3.0/gtk.css + gtk-4.0/gtk.css + index.theme).
# Substitutes pywal-style {placeholders} in ~/.config/wal/templates/colors-gtk[34].css
# against the active palette, scales border-radius to Hyprland's decoration:rounding,
# writes the theme directly to ~/.local/share/themes/Pywal16-Gtk/.

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PALETTE = Path(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
               os.environ.get("HYPR_STATE_HOME",
                              os.path.expanduser("~/.local/state/hypr")) + "/active-palette.json")
TEMPLATES = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "wal" / "templates"
OUT_DIR = Path(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))) / "themes" / "Pywal16-Gtk"

BORDER_RADIUS_FULL = re.compile(r"border-radius:\s*([0-9]+)px")
BORDER_RADIUS_QUAD = re.compile(r"border-radius:\s*([0-9]+)px\s+([0-9]+)px\s+([0-9]+)px\s+([0-9]+)px")

def cache_hit(h):
    return subprocess.run(["render-cache", "hit?", "gtk", h]).returncode == 0
def cache_store(h):
    subprocess.run(["render-cache", "store", "gtk", h])

class _KeepMissing(dict):
    def __missing__(self, key):
        return "{" + key + "}"

def substitute(template: str, vars_: dict) -> str:
    # Templates use Python str.format syntax: {name} is a placeholder, {{/}} are literal braces.
    return template.format_map(_KeepMissing(vars_))

def scale_radius(content: str, r: int) -> str:
    if r <= 0:
        return content
    def scale_one(px: int) -> int:
        # Mirror wal.gtk.sh's awk table: 12 -> 2r, 6 -> r, etc.
        table = {14: r*7//3, 12: r*2, 10: r*5//3, 9: r + r//2, 8: r*4//3,
                 7: r*7//6,  6: r,    5: r*5//6,  4: r*2//3,    3: r//2,
                 2: r//3,    1: r//6}
        return table.get(px, px)
    def sub_quad(m):
        a, b, c, d = (int(m.group(i)) for i in (1, 2, 3, 4))
        return f"border-radius: {scale_one(a)}px {scale_one(b)}px {scale_one(c)}px {scale_one(d)}px"
    content = BORDER_RADIUS_QUAD.sub(sub_quad, content)
    def sub_one(m):
        return f"border-radius: {scale_one(int(m.group(1)))}px"
    content = BORDER_RADIUS_FULL.sub(sub_one, content)
    return content

def hypr_border_radius() -> int:
    try:
        out = subprocess.run(["hyprctl", "-j", "getoption", "decoration:rounding"],
                             capture_output=True, text=True, check=True).stdout
        return int(json.loads(out).get("int", 8))
    except Exception:
        return 8

def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.replace(tmp, path)
    finally:
        if Path(tmp).exists():
            try: Path(tmp).unlink()
            except FileNotFoundError: pass

def main():
    if not PALETTE.is_file():
        sys.exit(f"render/gtk: missing {PALETTE}")
    p = json.loads(PALETTE.read_text())

    vars_ = {"background": p["bg"], "foreground": p["fg"]}
    for i, c in enumerate(p["colors"]):
        vars_[f"color{i}"] = c
    if "cursor" in p:
        vars_["cursor"] = p["cursor"]

    radius = hypr_border_radius()

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    for t in ("colors-gtk3.css", "colors-gtk4.css"):
        tp = TEMPLATES / t
        if tp.is_file(): hasher.update(tp.read_bytes())
    hasher.update(str(radius).encode())
    hasher.update(Path(__file__).read_bytes())
    h = hasher.hexdigest()[:16]

    if cache_hit(h) and (OUT_DIR / "gtk-3.0" / "gtk.css").exists() and (OUT_DIR / "gtk-4.0" / "gtk.css").exists():
        return

    for template_name, out_subdir in (("colors-gtk3.css", "gtk-3.0"), ("colors-gtk4.css", "gtk-4.0")):
        tp = TEMPLATES / template_name
        if not tp.is_file():
            print(f"render/gtk: missing template {tp}", file=sys.stderr)
            continue
        content = tp.read_text()
        content = substitute(content, vars_)
        content = scale_radius(content, radius)
        # Header note + write
        out = f"/* Hyprland border radius: {radius}px */\n\n{content}"
        out_path = OUT_DIR / out_subdir / "gtk.css"
        atomic_write(out_path, out)
        # gtk-dark.css symlink for the dark-variant lookup path
        dark_link = OUT_DIR / out_subdir / "gtk-dark.css"
        if dark_link.is_symlink() or dark_link.exists():
            dark_link.unlink()
        dark_link.symlink_to("gtk.css")

    # index.theme metadata (idempotent if already correct)
    index = OUT_DIR / "index.theme"
    if not index.is_file():
        atomic_write(index, """[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Pywal16-Gtk
Comment=Dynamic GTK theme generated from active palette
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Pywal16-Gtk
MetacityTheme=Pywal16-Gtk
IconTheme=Adwaita
CursorTheme=Adwaita
ButtonLayout=close,minimize,maximize:menu
""")

    cache_store(h)

    # Best-effort: poke xsettingsd if present
    try:
        subprocess.run(["pkill", "-HUP", "-x", "xsettingsd"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass

if __name__ == "__main__":
    main()
