#!/usr/bin/env python3
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from _common import XDG_DATA_HOME, atomic_write, cache_hit, cache_store, palette_path, short_digest
from _gtk_assets import install_gtk_theme_assets
from _gtk_compile import GTK_SOURCE_DIR, GTK_VERSIONS, compile_gtk_theme

PALETTE_FILE = palette_path()
GTK_THEME_DIR = XDG_DATA_HOME / "themes" / "Hypr-Gtk"
APP = "gtk"

# Sweet is vendored untouched; gtk-themes/sweet.patch carries every local change.
SWEET_SOURCE_DIR = GTK_SOURCE_DIR / "sweet"
INDEX_THEME = """[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Hypr-Gtk
Comment=Dynamic GTK theme generated from active palette
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Hypr-Gtk
MetacityTheme=Hypr-Gtk
IconTheme=Adwaita
CursorTheme=Adwaita
ButtonLayout=close,minimize,maximize:menu
"""
FALLBACK_BORDER_RADIUS = 8


def read_hyprland_border_radius() -> int:
    try:
        out = subprocess.run(["hyprctl", "-j", "getoption", "decoration:rounding"],
                             capture_output=True, text=True, check=True).stdout
        return int(json.loads(out).get("int", FALLBACK_BORDER_RADIUS))
    except Exception:
        return FALLBACK_BORDER_RADIUS

def gtk_input_digest(radius):
    hasher = hashlib.sha256()
    hasher.update(PALETTE_FILE.read_bytes())
    hasher.update(str(radius).encode())
    for renderer_file in (Path(__file__), Path(__file__).with_name("_gtk_compile.py"), Path(__file__).with_name("_gtk_assets.py")):
        hasher.update(renderer_file.read_bytes())
    hasher.update(str(max(f.stat().st_mtime_ns for f in GTK_SOURCE_DIR.rglob("*"))).encode())
    return short_digest(hasher)


def prepare_patched_sweet_sources(build_dir: Path) -> Path:
    source_dir = build_dir / "sweet"
    shutil.copytree(SWEET_SOURCE_DIR, source_dir)
    subprocess.run(["patch", "--batch", "--silent", "-p1", "-d", source_dir, "-i", GTK_SOURCE_DIR / "sweet.patch"], check=True)
    return source_dir


def install_gtk_stylesheets(stylesheets):
    for gtk, content in stylesheets.items():
        out_path = GTK_THEME_DIR / f"gtk-{gtk}" / "gtk.css"
        atomic_write(out_path, content)
        dark_link = out_path.with_name("gtk-dark.css")
        if dark_link.is_symlink() or dark_link.exists():
            dark_link.unlink()
        dark_link.symlink_to("gtk.css")


def toggle_gtk_reload_theme_name():
    # Each build switches desktop sync to this folder's other name, the only change that makes GTK 3 reload it.
    alias = GTK_THEME_DIR.with_name(f"{GTK_THEME_DIR.name}-Alt")
    if not alias.is_symlink():
        alias.symlink_to(GTK_THEME_DIR.name)
    name_file = GTK_THEME_DIR / "theme-name"
    previous = name_file.read_text().strip() if name_file.is_file() else GTK_THEME_DIR.name
    atomic_write(name_file, f"{GTK_THEME_DIR.name if previous == alias.name else alias.name}\n")


def ensure_gtk_theme_index():
    index = GTK_THEME_DIR / "index.theme"
    if not index.is_file():
        atomic_write(index, INDEX_THEME)


def main():
    if not PALETTE_FILE.is_file():
        sys.exit(f"render/gtk: missing {PALETTE_FILE}")
    palette = json.loads(PALETTE_FILE.read_text())
    radius = read_hyprland_border_radius()
    digest = gtk_input_digest(radius)
    if cache_hit(APP, digest) and all((GTK_THEME_DIR / f"gtk-{gtk}" / "gtk.css").exists() for gtk in GTK_VERSIONS):
        return

    with tempfile.TemporaryDirectory() as build_dir:
        source_dir = prepare_patched_sweet_sources(Path(build_dir))
        compiled_theme = compile_gtk_theme(source_dir, palette, radius)
        install_gtk_theme_assets(source_dir, compiled_theme, GTK_THEME_DIR)
        install_gtk_stylesheets(compiled_theme.stylesheets)
    toggle_gtk_reload_theme_name()
    ensure_gtk_theme_index()
    cache_store(APP, digest)

if __name__ == "__main__":
    main()
