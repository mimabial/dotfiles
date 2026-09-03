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
    """Resolve a shell's literal kvconfig colors through its colors.map."""

    def __init__(self, general, substitutions):
        self._general = general
        self._substitutions = substitutions

    def color(self, key):
        target = self._general.get(key)
        if not target:
            return None
        return self._substitutions.get(target, target)

    def role(self, key, default_var, colors, fg):
        return self.color(key) or colors.get(default_var, fg)


def _resolve_shared_roles(source, bg, fg, colors):
    accent = source.role("highlight.color", "color4", colors, fg)
    highlight_text = source.color("highlight.text.color") or contrast_text(
        bg, fg, accent
    )
    return {
        "accent": accent,
        "inactive_accent": source.color("inactive.highlight.color") or accent,
        "link": source.role("link.color", "color4", colors, fg),
        "link_visited": source.role("link.visited.color", "color5", colors, fg),
        "hover": colors.get("color12", accent),
        "highlight_text": highlight_text,
        "inactive_highlight_text": highlight_text,
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


def palette_to_pywal(palette):
    """active-palette.json -> the pywal shape QtRoles consumes."""
    return {
        "special": {"background": palette["bg"], "foreground": palette["fg"]},
        "colors": {
            f"color{index}": color for index, color in enumerate(palette["colors"])
        },
    }


class QtRoles:
    """Resolved Qt palette roles from the active palette + the shell's kvconfig.

    The palette is the only colour authority. The shell contributes geometry and,
    through its colours.map, which of its literals stands for which palette role.
    """

    def __init__(self, *, pywal, kvconfig_path=None, colors_map_path=None):
        self._general = _parse_general_colors(kvconfig_path)

        bg = pywal["special"]["background"]
        fg = pywal["special"]["foreground"]
        self.colors = pywal["colors"]
        palette_full = {**self.colors, "background": bg, "foreground": fg}
        self.substitutions = _load_colors_map(colors_map_path, palette_full)
        source = _RoleSource(self._general, self.substitutions)

        self.bg = bg
        self.fg = fg
        self.is_dark = luminance(bg) < 0.5
        resolved = _resolve_shared_roles(source, bg, fg, self.colors)
        resolved.update(_resolve_roles(bg, fg, self.colors, self.is_dark))
        for name, value in resolved.items():
            setattr(self, name, value)
