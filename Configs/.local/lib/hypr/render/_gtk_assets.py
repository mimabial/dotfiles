#!/usr/bin/env python3
import math
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

from _gtk_compile import CompiledGtkTheme

ASSET_SHEETS = ("src/gtk3/gtk3-assets.svg", "src/gtk3/gtk3-assets-dark.svg")
SVG = "{http://www.w3.org/2000/svg}"
INKSCAPE_LABEL = "{http://www.inkscape.org/namespaces/inkscape}label"
TRANSLATE = re.compile(r"translate\((-?[\d.]+)[ ,]*(-?[\d.]*)\)")
# gdk-pixbuf only recognises an unprefixed <svg> root as an SVG image.
ET.register_namespace("", SVG[1:-1])


def recolor_svg_gradients(root: ET.Element, colors: dict) -> None:
    nodes = {node.get("id"): node for node in root.iter()}
    for name in colors.keys() & nodes.keys():
        for stop in nodes[name].iter(f"{SVG}stop"):
            stop.set("stop-color", colors[name])


def render_png_assets_from_sheet(svg_path: Path, gradient_colors: dict, asset_names: set[str], destination_dir: Path) -> None:
    import gi
    gi.require_version("Rsvg", "2.0")
    from gi.repository import Rsvg
    import cairo

    root = ET.parse(svg_path).getroot()
    recolor_svg_gradients(root, gradient_colors)
    parents = {child: parent for parent in root.iter() for child in parent}
    handle = Rsvg.Handle.new_from_data(ET.tostring(root))
    _, sheet_width, sheet_height = handle.get_intrinsic_size_in_pixels()
    viewport, rendered_sheets = Rsvg.Rectangle(), {}
    # Each asset is the whole sheet cropped to a hidden "Baseplate" rect, named by the icon-name text beside it.
    for layer in root.iter(f"{SVG}g"):
        if not layer.get(INKSCAPE_LABEL, "").startswith("Baseplate"):
            continue
        name = "".join(next(text for text in layer.iter(f"{SVG}text") if text.get(INKSCAPE_LABEL) == "icon-name").itertext()).strip()
        if name not in asset_names:
            continue
        rect = next(layer.iter(f"{SVG}rect"))
        x, y, node = float(rect.get("x", 0)), float(rect.get("y", 0)), rect
        while node is not None:
            if shift := TRANSLATE.fullmatch(node.get("transform", "")):
                x, y = x + float(shift[1]), y + float(shift[2] or 0)
            node = parents.get(node)
        for scale, suffix in ((1, ""), (2, "@2")):
            if scale not in rendered_sheets:
                viewport.width, viewport.height = sheet_width * scale, sheet_height * scale
                rendered_sheets[scale] = cairo.ImageSurface(cairo.FORMAT_ARGB32, math.ceil(viewport.width), math.ceil(viewport.height))
                handle.render_document(cairo.Context(rendered_sheets[scale]), viewport)
            surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, math.ceil(float(rect.get("width")) * scale),
                                         math.ceil(float(rect.get("height")) * scale))
            context = cairo.Context(surface)
            context.set_source_surface(rendered_sheets[scale], -x * scale, -y * scale)
            context.paint()
            surface.write_to_png(str(destination_dir / f"{name}{suffix}.png"))


def install_gtk_theme_assets(source_dir: Path, compiled_theme: CompiledGtkTheme, theme_dir: Path) -> None:
    assets_dir = theme_dir / "assets"
    shutil.rmtree(assets_dir, ignore_errors=True)
    shutil.copytree(source_dir / "assets", assets_dir)
    for image in (assets_dir).glob("*.svg"):
        text = image.read_text()
        if any(f'id="{name}"' in text for name in compiled_theme.gradient_colors):
            tree = ET.parse(image)
            recolor_svg_gradients(tree.getroot(), compiled_theme.gradient_colors)
            tree.write(image)
    asset_names = set(re.findall(r'url\("\.\./assets/([\w-]+?)(?:@2)?\.png"\)', "".join(compiled_theme.stylesheets.values())))
    for sheet in ASSET_SHEETS:
        render_png_assets_from_sheet(source_dir / sheet, compiled_theme.gradient_colors, asset_names, assets_dir)
