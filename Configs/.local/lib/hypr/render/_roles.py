"""Shared Qt palette role resolution for render/*.py and install_kvantum_theme.py.

Theme mode is source-first: Qt/KDE roles come from the pack's
kvconfig.theme [GeneralColors] and colors.map. Wallpaper mode keeps generated
fallbacks because there is no fixed theme source palette.
"""

import os
import re


def hex_to_rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def luminance(hex_):
    r, g, b = (c / 255 for c in hex_to_rgb(hex_))
    return 0.299 * r + 0.587 * g + 0.114 * b


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
    with open(kvconfig_path) as f:
        content = f.read()
    sec = re.search(r"(?ms)^\[GeneralColors\]\n(.*?)(?=^\[|\Z)", content)
    if not sec:
        return {}
    result = {}
    for m in re.finditer(
        r"^([a-z._]+)\s*=\s*(#[0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?",
        sec.group(1),
        re.MULTILINE,
    ):
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


class _RoleSource:
    """Resolve kvconfig colors either literally or through colors.map."""

    def __init__(self, general, substitutions, theme_mode):
        self._general = general
        self._substitutions = substitutions
        self._theme_mode = theme_mode

    def color(self, key):
        target = self._general.get(key)
        if not target:
            return None
        if self._theme_mode:
            return target
        return self._substitutions.get(target, target)

    def role(self, key, default_var, colors, fg):
        return self.color(key) or colors.get(default_var, fg)


def _resolve_theme_base(source, bg, fg):
    bg = source.color("window.color") or bg
    fg = source.color("text.color") or source.color("window.text.color") or fg
    if not fg and bg:
        fg = "#e0e0e0" if luminance(bg) < 0.5 else "#202020"
    return bg, fg


def _resolve_shared_roles(source, bg, fg, colors, is_dark, theme_mode):
    accent = source.role("highlight.color", "color4", colors, fg)
    highlight_text = source.color("highlight.text.color") or contrast_text(
        bg, fg, accent
    )
    return {
        "accent": accent,
        "inactive_accent": source.color("inactive.highlight.color") or accent,
        "link": source.role("link.color", "color4", colors, fg),
        "link_visited": source.role("link.visited.color", "color5", colors, fg),
        "hover": accent if theme_mode else colors.get("color12", accent),
        "highlight_text": highlight_text,
        "inactive_highlight_text": highlight_text,
    }


def _resolve_theme_roles(source, bg, fg, is_dark):
    window_surface = source.color("window.color") or bg
    base_surface = source.color("base.color") or window_surface
    alternate_surface = source.color("alt.base.color") or base_surface
    text = source.color("text.color") or fg
    return {
        "window_surface": window_surface,
        "base_surface": base_surface,
        "alternate_surface": alternate_surface,
        "button_surface": source.color("button.color") or base_surface,
        "normal_surface": base_surface,
        "tooltip_surface": source.color("tooltip.base.color") or alternate_surface,
        "text": text,
        "window_text": source.color("window.text.color") or text,
        "button_text": source.color("button.text.color") or text,
        "disabled_text": (
            source.color("disabled.text.color")
            or source.color("text.disabled.color")
            or shade(text, 0.18 * (-1 if is_dark else 1))
        ),
        "tooltip_text": source.color("tooltip.text.color") or text,
        "bright_text": source.color("progress.indicator.text.color")
        or ("#ffffff" if is_dark else "#000000"),
        "light": source.color("light.color"),
        "mid_light": source.color("mid.light.color"),
        "dark": source.color("dark.color"),
        "mid": source.color("mid.color"),
        "shadow": None,
    }


def _resolve_wallpaper_roles(bg, fg, colors, is_dark):
    normal_surface = colors.get("color0", bg) if is_dark else colors.get("color7", bg)
    return {
        "normal_surface": normal_surface,
        "window_surface": bg,
        "base_surface": bg,
        "alternate_surface": None,
        "button_surface": normal_surface,
        "tooltip_surface": normal_surface,
        "text": fg,
        "window_text": fg,
        "button_text": fg,
        "disabled_text": shade(fg, 0.18 * (-1 if is_dark else 1)),
        "tooltip_text": fg,
        "bright_text": "#ffffff" if is_dark else "#000000",
        "light": None,
        "mid_light": None,
        "dark": None,
        "mid": None,
        "shadow": None,
    }


class QtRoles:
    """Resolved Qt palette roles from an active palette + pack kvconfig."""

    def __init__(self, *, pywal, theme_mode, kvconfig_path=None, colors_map_path=None):
        self.theme_mode = theme_mode
        self._general = _parse_general_colors(kvconfig_path)

        bg = pywal["special"]["background"]
        fg = pywal["special"]["foreground"]
        self.colors = pywal["colors"]
        palette_full = {**self.colors, "background": bg, "foreground": fg}
        self.substitutions = _load_colors_map(colors_map_path, palette_full)
        source = _RoleSource(self._general, self.substitutions, theme_mode)

        if theme_mode:
            bg, fg = _resolve_theme_base(source, bg, fg)

        self.bg = bg
        self.fg = fg
        self.is_dark = luminance(bg) < 0.5
        resolved = _resolve_shared_roles(
            source, bg, fg, self.colors, self.is_dark, theme_mode
        )
        if theme_mode:
            resolved.update(_resolve_theme_roles(source, bg, fg, self.is_dark))
        else:
            resolved.update(_resolve_wallpaper_roles(bg, fg, self.colors, self.is_dark))
        for name, value in resolved.items():
            setattr(self, name, value)
