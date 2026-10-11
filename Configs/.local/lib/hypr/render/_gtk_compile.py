#!/usr/bin/env python3
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import NamedTuple

GTK_SOURCE_DIR = Path(__file__).resolve().parent / "gtk-themes"
GTK_VERSIONS = ("3.0", "4.0")
STYLESHEET_SOURCES = {"dark": "gtk-{gtk}/gtk-dark.scss", "light": "gtk-{gtk}/gtk.scss"}
# Named gradient or stop in Sweet's SVGs -> the theme value it takes.
ASSET_GRADIENT_EXPRESSIONS = {"color-accent": "$selected_bg_color", "color-cyan": "$hypr-cyan", "color-on-accent": "$selected_fg_color",
             "color-box": "hypr-surface(#40424C, $hypr-window)", "color-switch-from": "$orange", "color-switch-to": "$yellow"}


class CompiledGtkTheme(NamedTuple):
    stylesheets: dict[str, str]
    gradient_colors: dict[str, str]


def render_palette_sass_variables(palette: dict, border_radius: int) -> str:
    ink_dark, ink_light = (palette["fg"], palette["bg"]) if palette["background"] == "light" else (palette["bg"], palette["fg"])
    colors = palette["colors"]
    values = {"bg": palette["bg"], "fg": palette["fg"], "ink-dark": ink_dark, "ink-light": ink_light, "accent": colors[4],
              "red": colors[1], "green": colors[2], "yellow": colors[3], "purple": colors[5], "cyan": colors[6],
              "radius": f"{border_radius}px"}
    return "".join(f"$hypr-{name}: {value};\n" for name, value in values.items())


def compile_sass_stylesheet(source: str) -> str:
    run = subprocess.run(["sassc", "--stdin", "-M", "-t", "expanded", "-I", str(GTK_SOURCE_DIR)],
                         input=source, capture_output=True, text=True)
    if run.returncode:
        sys.exit(f"render/gtk: sassc: {run.stderr.strip()}")
    return run.stdout


def compile_gtk_theme(source_dir: Path, palette: dict, border_radius: int) -> CompiledGtkTheme:
    palette_sass = render_palette_sass_variables(palette, border_radius)
    variant = "light" if palette["background"] == "light" else "dark"
    # Gradients are evaluated in Sweet's own scope, as a rule trailing the first stylesheet that is split off again.
    sources = [f'{palette_sass}@import "{source_dir / STYLESHEET_SOURCES[variant].format(gtk=gtk)}";\n' for gtk in GTK_VERSIONS]
    sources[0] += "hypr-gradients {" + "".join(f"{name}: {value};" for name, value in ASSET_GRADIENT_EXPRESSIONS.items()) + "}"
    with ThreadPoolExecutor() as pool:
        stylesheets = list(pool.map(compile_sass_stylesheet, sources))
    stylesheets[0], _, gradient_declarations = stylesheets[0].partition("hypr-gradients {")
    return CompiledGtkTheme(dict(zip(GTK_VERSIONS, stylesheets)), dict(re.findall(r"([\w-]+): ([^;]+);", gradient_declarations)))
