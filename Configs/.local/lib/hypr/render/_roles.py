"""Shared Qt palette role resolution for render/*.py and install_kvantum_theme.py.

Resolves bg, fg, accent, link, link_visited, and colors.map substitutions from
active-palette.json + the pack's kvconfig.theme + colors.map.
"""

import os
import re


def hex_to_rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def luminance(hex_):
    r, g, b = (c / 255 for c in hex_to_rgb(hex_))
    return 0.299 * r + 0.587 * g + 0.114 * b


def contrast_text(bg, fg, against):
    return bg if abs(luminance(fg) - luminance(against)) < abs(luminance(bg) - luminance(against)) else fg


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
    with open(kvconfig_path) as f:
        content = f.read()
    sec = re.search(r"(?ms)^\[GeneralColors\]\n(.*?)(?=^\[|\Z)", content)
    if not sec:
        return {}
    result = {}
    for m in re.finditer(r"^([a-z._]+)\s*=\s*(#[0-9a-fA-F]{6})", sec.group(1), re.M):
        result[m.group(1)] = m.group(2).lower()
    return result


def _load_colors_map(colors_map_path, palette_full):
    subs = {}
    if not colors_map_path or not os.path.exists(colors_map_path):
        return subs
    with open(colors_map_path) as f:
        for line in f:
            line = line.strip()
            if "=" not in line:
                continue
            hex_part, _, var = line.partition("=")
            hex_part = hex_part.strip()
            var = var.strip()
            if not re.fullmatch(r"#[0-9a-fA-F]{6}", hex_part):
                continue
            if var not in palette_full:
                continue
            subs[hex_part.lower()] = palette_full[var]
    return subs


class QtRoles:
    """Resolved Qt palette roles from an active palette + pack kvconfig."""

    def __init__(self, *, pywal, theme_mode, kvconfig_path=None, colors_map_path=None):
        self.theme_mode = theme_mode
        self._general = _parse_general_colors(kvconfig_path)

        bg = pywal["special"]["background"]
        fg = pywal["special"]["foreground"]
        colors = pywal["colors"]

        if theme_mode:
            pack_bg = self._general.get("window.color")
            pack_fg = self._general.get("window.text.color") or self._general.get("text.color")
            if pack_bg:
                bg = pack_bg
            if pack_fg:
                fg = pack_fg
            elif pack_bg:
                fg = "#e0e0e0" if luminance(pack_bg) < 0.5 else "#202020"

        self.bg = bg
        self.fg = fg
        self.colors = colors
        self.is_dark = luminance(bg) < 0.5

        palette_full = {**colors, "background": bg, "foreground": fg}
        self.substitutions = _load_colors_map(colors_map_path, palette_full)

        self.accent = self._resolve_role("highlight.color", "color4")
        self.link = self._resolve_role("link.color", "color4")
        self.link_visited = self._resolve_role("link.visited.color", "color5")
        self.hover = colors.get("color12", self.accent)
        self.highlight_text = contrast_text(bg, fg, self.accent)

        if theme_mode:
            self.normal_surface = (
                self._general.get("alt.base.color")
                or self._general.get("base.color")
                or bg
            )
            self.button_surface = self.normal_surface
        else:
            self.normal_surface = (
                colors.get("color0", bg) if self.is_dark
                else colors.get("color7", bg)
            )
            self.button_surface = self.normal_surface

    def _resolve_role(self, key, default_var):
        target = self._general.get(key)
        if not target:
            return self.colors.get(default_var, self.fg)
        if self.theme_mode:
            return target
        return self.substitutions.get(target, target)
