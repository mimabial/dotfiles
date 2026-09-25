#!/usr/bin/env python3
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store

PALETTE = Path(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
               os.environ.get("HYPR_STATE_HOME",
                              os.path.expanduser("~/.local/state/hypr")) + "/active-palette.json")
OUT_DIR = Path(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))) / "themes" / "Pywal16-Gtk"
THEMES = Path(__file__).resolve().parent / "gtk-themes"
GTK_VERSIONS = ("3.0", "4.0")

APP = "gtk"

# Sweet is vendored untouched; gtk-themes/sweet.patch carries every local change.
SWEET = THEMES / "sweet"
STYLESHEETS = {"dark": "gtk-{gtk}/gtk-dark.scss", "light": "gtk-{gtk}/gtk.scss"}
SHEETS = ("src/gtk3/gtk3-assets.svg", "src/gtk3/gtk3-assets-dark.svg")
# Named gradient or stop in Sweet's SVGs -> the theme value it takes.
GRADIENTS = {"color-accent": "$selected_bg_color", "color-cyan": "$hypr-cyan", "color-on-accent": "$selected_fg_color",
             "color-box": "hypr-surface(#40424C, $hypr-window)", "color-switch-from": "$orange", "color-switch-to": "$yellow"}
SVG = "{http://www.w3.org/2000/svg}"
INKSCAPE_LABEL = "{http://www.inkscape.org/namespaces/inkscape}label"
TRANSLATE = re.compile(r"translate\((-?[\d.]+)[ ,]*(-?[\d.]*)\)")
# gdk-pixbuf only recognises an unprefixed <svg> root as an SVG image.
ET.register_namespace("", SVG[1:-1])


def sass_palette(p: dict, radius: int) -> str:
    ink_dark, ink_light = (p["fg"], p["bg"]) if p["background"] == "light" else (p["bg"], p["fg"])
    colors = p["colors"]
    values = {"bg": p["bg"], "fg": p["fg"], "ink-dark": ink_dark, "ink-light": ink_light, "accent": colors[4],
              "red": colors[1], "green": colors[2], "yellow": colors[3], "purple": colors[5], "cyan": colors[6],
              "radius": f"{radius}px"}
    return "".join(f"$hypr-{name}: {value};\n" for name, value in values.items())


def sassc(source: str) -> str:
    run = subprocess.run(["sassc", "--stdin", "-M", "-t", "expanded", "-I", str(THEMES)],
                         input=source, capture_output=True, text=True)
    if run.returncode:
        sys.exit(f"render/gtk: sassc: {run.stderr.strip()}")
    return run.stdout


def compile_theme(source: Path, palette: str, variant: str) -> tuple[dict, dict]:
    # Gradients are evaluated in Sweet's own scope, as a rule trailing the first stylesheet that is split off again.
    sources = [f'{palette}@import "{source / STYLESHEETS[variant].format(gtk=gtk)}";\n' for gtk in GTK_VERSIONS]
    sources[0] += "hypr-gradients {" + "".join(f"{name}: {value};" for name, value in GRADIENTS.items()) + "}"
    with ThreadPoolExecutor() as pool:
        stylesheets = list(pool.map(sassc, sources))
    stylesheets[0], _, probed = stylesheets[0].partition("hypr-gradients {")
    return dict(zip(GTK_VERSIONS, stylesheets)), dict(re.findall(r"([\w-]+): ([^;]+);", probed))


def recolor(root: ET.Element, colors: dict) -> None:
    nodes = {node.get("id"): node for node in root.iter()}
    for name in colors.keys() & nodes.keys():
        for stop in nodes[name].iter(f"{SVG}stop"):
            stop.set("stop-color", colors[name])


def render_sheet(svg: Path, colors: dict, names: set, destination: Path) -> None:
    import gi
    gi.require_version("Rsvg", "2.0")
    from gi.repository import Rsvg
    import cairo

    root = ET.parse(svg).getroot()
    recolor(root, colors)
    parents = {child: parent for parent in root.iter() for child in parent}
    handle = Rsvg.Handle.new_from_data(ET.tostring(root))
    _, sheet_width, sheet_height = handle.get_intrinsic_size_in_pixels()
    sheet, whole_sheet = Rsvg.Rectangle(), {}
    # Each asset is the whole sheet cropped to a hidden "Baseplate" rect, named by the icon-name text beside it.
    for layer in root.iter(f"{SVG}g"):
        if not layer.get(INKSCAPE_LABEL, "").startswith("Baseplate"):
            continue
        name = "".join(next(text for text in layer.iter(f"{SVG}text") if text.get(INKSCAPE_LABEL) == "icon-name").itertext()).strip()
        if name not in names:
            continue
        rect = next(layer.iter(f"{SVG}rect"))
        x, y, node = float(rect.get("x", 0)), float(rect.get("y", 0)), rect
        while node is not None:
            if shift := TRANSLATE.fullmatch(node.get("transform", "")):
                x, y = x + float(shift[1]), y + float(shift[2] or 0)
            node = parents.get(node)
        for scale, suffix in ((1, ""), (2, "@2")):
            if scale not in whole_sheet:
                sheet.width, sheet.height = sheet_width * scale, sheet_height * scale
                whole_sheet[scale] = cairo.ImageSurface(cairo.FORMAT_ARGB32, math.ceil(sheet.width), math.ceil(sheet.height))
                handle.render_document(cairo.Context(whole_sheet[scale]), sheet)
            surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, math.ceil(float(rect.get("width")) * scale),
                                         math.ceil(float(rect.get("height")) * scale))
            context = cairo.Context(surface)
            context.set_source_surface(whole_sheet[scale], -x * scale, -y * scale)
            context.paint()
            surface.write_to_png(str(destination / f"{name}{suffix}.png"))


def hypr_border_radius() -> int:
    try:
        out = subprocess.run(["hyprctl", "-j", "getoption", "decoration:rounding"],
                             capture_output=True, text=True, check=True).stdout
        return int(json.loads(out).get("int", 8))
    except Exception:
        return 8

def main():
    if not PALETTE.is_file():
        sys.exit(f"render/gtk: missing {PALETTE}")
    palette = json.loads(PALETTE.read_text())
    radius = hypr_border_radius()

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    hasher.update(str(radius).encode())
    hasher.update(Path(__file__).read_bytes())
    hasher.update(str(max(f.stat().st_mtime_ns for f in THEMES.rglob("*"))).encode())
    digest = hasher.hexdigest()[:16]

    if cache_hit(APP, digest) and all((OUT_DIR / f"gtk-{gtk}" / "gtk.css").exists() for gtk in GTK_VERSIONS):
        return

    with tempfile.TemporaryDirectory() as build:
        source = Path(build) / "sweet"
        shutil.copytree(SWEET, source)
        subprocess.run(["patch", "--batch", "--silent", "-p1", "-d", source, "-i", THEMES / "sweet.patch"], check=True)
        stylesheets, gradient_colors = compile_theme(source, sass_palette(palette, radius), "light" if palette["background"] == "light" else "dark")

        shutil.rmtree(OUT_DIR / "assets", ignore_errors=True)
        shutil.copytree(source / "assets", OUT_DIR / "assets")
        for image in (OUT_DIR / "assets").glob("*.svg"):
            text = image.read_text()
            if any(f'id="{name}"' in text for name in gradient_colors):
                tree = ET.parse(image)
                recolor(tree.getroot(), gradient_colors)
                tree.write(image)
        asset_names = set(re.findall(r'url\("\.\./assets/([\w-]+?)(?:@2)?\.png"\)', "".join(stylesheets.values())))
        for sheet in SHEETS:
            render_sheet(source / sheet, gradient_colors, asset_names, OUT_DIR / "assets")

    for gtk, content in stylesheets.items():
        out_path = OUT_DIR / f"gtk-{gtk}" / "gtk.css"
        atomic_write(out_path, content)
        dark_link = out_path.with_name("gtk-dark.css")
        if dark_link.is_symlink() or dark_link.exists():
            dark_link.unlink()
        dark_link.symlink_to("gtk.css")

    # Each build switches desktop sync to this folder's other name, the only change that makes GTK 3 reload it.
    alias = OUT_DIR.with_name(f"{OUT_DIR.name}-Alt")
    if not alias.is_symlink():
        alias.symlink_to(OUT_DIR.name)
    name_file = OUT_DIR / "theme-name"
    previous = name_file.read_text().strip() if name_file.is_file() else OUT_DIR.name
    atomic_write(name_file, f"{OUT_DIR.name if previous == alias.name else alias.name}\n")

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

    cache_store(APP, digest)

if __name__ == "__main__":
    main()
