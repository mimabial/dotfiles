"""Qt/KDE roles map the selected Kvantum shell's literals to the active palette."""

import hashlib
import os
import re
from pathlib import Path

from _common import HEX_COLOR, LIGHT_LUMINANCE_THRESHOLD, hex_to_rgb, luminance, short_digest

ALTERNATE_SURFACE_SHADE = 0.06
DISABLED_TEXT_SHADE = 0.18


def contrast_text(bg, fg, against):
    return (
        bg
        if abs(luminance(fg) - luminance(against))
        < abs(luminance(bg) - luminance(against))
        else fg
    )


def shade(hex_, amount):
    r, g, b = hex_to_rgb(hex_)
    if amount >= 0:
        r = round(r + (255 - r) * amount)
        g = round(g + (255 - g) * amount)
        b = round(b + (255 - b) * amount)
    else:
        r = round(r * (1 + amount))
        g = round(g * (1 + amount))
        b = round(b * (1 + amount))
    return f"#{r:02x}{g:02x}{b:02x}"


def _parse_general_colors(kvconfig_path):
    if not kvconfig_path or not os.path.exists(kvconfig_path):
        return {}
    with open(kvconfig_path) as config_file:
        config_text = config_file.read()
    section_match = re.search(r"(?ms)^\[GeneralColors\]\n(.*?)(?=^\[|\Z)", config_text)
    if not section_match:
        return {}
    return {
        color_match["color_key"]: color_match["color_hex"].lower()
        for color_match in re.finditer(
            r"^(?P<color_key>[a-z._]+)\s*=\s*(?P<color_hex>#[0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?",
            section_match[1],
            re.MULTILINE,
        )
    }


def _load_colors_map(colors_map_path, palette_by_role):
    color_substitutions = {}
    if not colors_map_path or not os.path.exists(colors_map_path):
        return color_substitutions
    with open(colors_map_path) as mapping_file:
        for line in mapping_file:
            line = line.strip()
            if "=" not in line:
                continue
            source_hex, _, replacement = line.partition("=")
            source_hex = source_hex.strip()
            replacement = replacement.strip()
            if not HEX_COLOR.fullmatch(source_hex):
                continue
            if HEX_COLOR.fullmatch(replacement):
                color_substitutions[source_hex.lower()] = replacement.lower()
            elif replacement in palette_by_role:
                color_substitutions[source_hex.lower()] = palette_by_role[replacement]
    return color_substitutions


class _RoleSource:

    def __init__(self, general_colors, color_substitutions):
        self._general_colors = general_colors
        self._color_substitutions = color_substitutions

    def color(self, color_key):
        source_color = self._general_colors.get(color_key)
        if not source_color:
            return None
        return self._color_substitutions.get(source_color, source_color)

    def role(self, color_key, fallback_palette_role, palette_colors, fallback_color):
        return self.color(color_key) or palette_colors.get(fallback_palette_role, fallback_color)


def _resolve_shared_roles(source, bg, fg, colors):
    accent = source.role("highlight.color", "color4", colors, fg)
    highlight_text = source.color("highlight.text.color") or contrast_text(
        bg, fg, accent
    )
    return {
        "accent": accent,
        "link": source.role("link.color", "color4", colors, fg),
        "link_visited": source.role("link.visited.color", "color5", colors, fg),
        "hover": colors.get("color12", accent),
        "highlight_text": highlight_text,
    }


def _resolve_roles(bg, fg, colors, is_dark):
    # color0/color7 are the palette's surface pair, but not every theme follows the
    # ANSI convention that color0 is the dark end -- some light packs put their ink
    # in color7. Pick by luminance so an inverted palette can't hand back its
    # darkest colour as a surface that then gets fg-coloured text drawn on it.
    pair = [color for color in (colors.get("color0"), colors.get("color7")) if color]
    normal_surface = (
        min(pair, key=lambda color: abs(luminance(color) - luminance(bg))) if pair else bg
    )
    return {
        "window_surface": bg,
        "base_surface": bg,
        "alternate_surface": shade(bg, ALTERNATE_SURFACE_SHADE * (1 if is_dark else -1)),
        "button_surface": normal_surface,
        "tooltip_surface": normal_surface,
        "text": fg,
        "window_text": fg,
        "button_text": fg,
        "disabled_text": shade(fg, DISABLED_TEXT_SHADE * (-1 if is_dark else 1)),
        "tooltip_text": fg,
    }


def palette_to_ansi_scheme(palette):
    return {
        "special": {"background": palette["bg"], "foreground": palette["fg"]},
        "colors": {
            f"color{index}": color for index, color in enumerate(palette["colors"])
        },
    }


class QtRoles:
    """The palette is the only colour authority. The shell's colours.map says which
    of its kvconfig literals stands for which palette role."""

    def __init__(self, *, scheme, kvconfig_path=None, colors_map_path=None):
        bg = scheme["special"]["background"]
        fg = scheme["special"]["foreground"]
        self.colors = scheme["colors"]
        palette_by_role = {**self.colors, "background": bg, "foreground": fg}
        source = _RoleSource(
            _parse_general_colors(kvconfig_path),
            _load_colors_map(colors_map_path, palette_by_role),
        )

        self.bg = bg
        self.is_dark = luminance(bg) < LIGHT_LUMINANCE_THRESHOLD
        resolved = _resolve_shared_roles(source, bg, fg, self.colors)
        resolved.update(_resolve_roles(bg, fg, self.colors, self.is_dark))
        for name, value in resolved.items():
            setattr(self, name, value)


def qt_roles_from_palette(palette, kvantum_files):
    return QtRoles(
        scheme=palette_to_ansi_scheme(palette),
        kvconfig_path=kvantum_files.kvconfig_path,
        colors_map_path=kvantum_files.color_map_path,
    )


def qt_role_inputs_digest(palette_path, kvantum_files, renderer_path):
    hasher = hashlib.sha256()
    hasher.update(palette_path.read_bytes())
    for path in (*kvantum_files, renderer_path, Path(__file__), Path(__file__).with_name("_kvantum.py"),
                 Path(__file__).with_name("_common.py")):
        if path and path.is_file():
            hasher.update(path.read_bytes())
    return short_digest(hasher)
