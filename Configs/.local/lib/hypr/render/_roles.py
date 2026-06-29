"""Shared Qt palette role resolution for render/*.py and install_kvantum_theme.py.

Theme mode is source-first: Qt/KDE roles come from the pack's
kvconfig.theme [GeneralColors] and colors.map. Wallpaper mode keeps generated
fallbacks because there is no fixed theme source palette.
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
    for m in re.finditer(r"^([a-z._]+)\s*=\s*(#[0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?", sec.group(1), re.M):
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
            if re.fullmatch(r"#[0-9a-fA-F]{6}", var):
                subs[hex_part.lower()] = var.lower()
            elif var in palette_full:
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

        palette_full = {**colors, "background": bg, "foreground": fg}
        self.substitutions = _load_colors_map(colors_map_path, palette_full)

        if theme_mode:
            bg = self._source_color("window.color") or bg
            fg = (
                self._source_color("text.color")
                or self._source_color("window.text.color")
                or fg
            )
            if not fg and bg:
                fg = "#e0e0e0" if luminance(bg) < 0.5 else "#202020"

        self.bg = bg
        self.fg = fg
        self.colors = colors
        self.is_dark = luminance(bg) < 0.5

        self.accent = self._resolve_role("highlight.color", "color4")
        self.inactive_accent = self._source_color("inactive.highlight.color") or self.accent
        self.link = self._resolve_role("link.color", "color4")
        self.link_visited = self._resolve_role("link.visited.color", "color5")
        self.hover = self.accent if theme_mode else colors.get("color12", self.accent)
        self.highlight_text = self._source_color("highlight.text.color") or contrast_text(bg, fg, self.accent)
        self.inactive_highlight_text = self.highlight_text

        if theme_mode:
            self.window_surface = self._source_color("window.color") or bg
            self.base_surface = self._source_color("base.color") or self.window_surface
            self.alternate_surface = self._source_color("alt.base.color") or self.base_surface
            self.button_surface = self._source_color("button.color") or self.base_surface
            self.normal_surface = self.base_surface
            self.tooltip_surface = (
                self._source_color("tooltip.base.color")
                or self.alternate_surface
            )
            self.text = self._source_color("text.color") or fg
            self.window_text = self._source_color("window.text.color") or self.text
            self.button_text = self._source_color("button.text.color") or self.text
            self.disabled_text = (
                self._source_color("disabled.text.color")
                or self._source_color("text.disabled.color")
                or shade(self.text, 0.18 * (-1 if self.is_dark else 1))
            )
            self.tooltip_text = self._source_color("tooltip.text.color") or self.text
            self.bright_text = self._source_color("progress.indicator.text.color") or (
                "#ffffff" if self.is_dark else "#000000"
            )
            self.light = self._source_color("light.color")
            self.mid_light = self._source_color("mid.light.color")
            self.dark = self._source_color("dark.color")
            self.mid = self._source_color("mid.color")
            self.shadow = None
        else:
            self.normal_surface = (
                colors.get("color0", bg) if self.is_dark
                else colors.get("color7", bg)
            )
            self.window_surface = bg
            self.base_surface = bg
            self.alternate_surface = None
            self.button_surface = self.normal_surface
            self.tooltip_surface = self.normal_surface
            self.text = fg
            self.window_text = fg
            self.button_text = fg
            self.disabled_text = shade(fg, 0.18 * (-1 if self.is_dark else 1))
            self.tooltip_text = fg
            self.bright_text = "#ffffff" if self.is_dark else "#000000"
            self.light = None
            self.mid_light = None
            self.dark = None
            self.mid = None
            self.shadow = None

    def _resolve_role(self, key, default_var):
        target = self._resolve_general_color(key)
        if not target:
            return self.colors.get(default_var, self.fg)
        return target

    def _resolve_general_color(self, key):
        target = self._general.get(key)
        if not target:
            return None
        if self.theme_mode:
            return target
        return self.substitutions.get(target, target)

    def _source_color(self, key):
        return self._resolve_general_color(key)
