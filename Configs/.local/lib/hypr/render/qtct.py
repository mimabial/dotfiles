#!/usr/bin/env python3
# Renderer: KDE KColorScheme + qt6ct palette generated from shared Qt roles.

import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store
from _roles import QtRoles, hex_to_rgb, shade

PALETTE = Path(
    sys.argv[1]
    if len(sys.argv) > 1 and sys.argv[1]
    else os.environ.get("HYPR_STATE_HOME", os.path.expanduser("~/.local/state/hypr"))
    + "/active-palette.json"
)
OUT_DIR = (
    Path(os.environ.get("HYPR_CACHE_HOME", os.path.expanduser("~/.cache/hypr")))
    / "render"
    / "qtct"
)
KDE_FILE = OUT_DIR / "Pywal.colors"
QTCT_FILE = OUT_DIR / "pywal16.conf"
THEMES_DIR = (
    Path(os.environ.get("HYPR_CONFIG_HOME", os.path.expanduser("~/.config/hypr")))
    / "themes"
)


def rgb(color):
    red, green, blue = hex_to_rgb(color)
    return f"{red},{green},{blue}"


def argb(color, alpha="ff"):
    return f"#{alpha}{color.lstrip('#').lower()}"


def qtct_line(values):
    return ", ".join(argb(color) for color in values)


def pack_role_files(palette):
    source = palette.get("source", "")
    if palette.get("mode", "wallpaper") != "theme" or not source.startswith("theme:"):
        return None, None

    pack_dir = THEMES_DIR / source.removeprefix("theme:")
    kvconfig = pack_dir / "kvantum" / "kvconfig.theme"
    colors_map = pack_dir / "kvantum" / "colors.map"
    return (
        kvconfig if kvconfig.is_file() else None,
        colors_map if colors_map.is_file() else None,
    )


def renderer_hash(pack_kvconfig, pack_colors_map):
    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    for path in (
        pack_kvconfig,
        pack_colors_map,
        Path(__file__),
        Path(__file__).with_name("_roles.py"),
    ):
        if path and path.is_file():
            hasher.update(path.read_bytes())
    return hasher.hexdigest()[:16]


def resolve_roles(palette, pack_kvconfig, pack_colors_map):
    pywal = {
        "special": {
            "background": palette["bg"],
            "foreground": palette["fg"],
        },
        "colors": {
            f"color{index}": color for index, color in enumerate(palette["colors"])
        },
    }
    return QtRoles(
        pywal=pywal,
        theme_mode=palette.get("mode", "wallpaper") == "theme",
        kvconfig_path=str(pack_kvconfig) if pack_kvconfig else None,
        colors_map_path=str(pack_colors_map) if pack_colors_map else None,
    )


def kde_sections(roles):
    direction = 1 if roles.is_dark else -1
    alternate_surface = roles.alternate_surface or shade(roles.bg, 0.06 * direction)
    shared = {
        "ForegroundActive": rgb(roles.accent),
        "ForegroundInactive": rgb(roles.disabled_text),
        "ForegroundLink": rgb(roles.link),
        "ForegroundVisited": rgb(roles.link_visited),
        "ForegroundNegative": rgb(roles.colors["color1"]),
        "ForegroundNeutral": rgb(roles.colors["color3"]),
        "ForegroundPositive": rgb(roles.colors["color2"]),
        "DecorationFocus": rgb(roles.accent),
        "DecorationHover": rgb(roles.hover),
    }
    selection = {
        "BackgroundNormal": rgb(roles.accent),
        "BackgroundAlternate": rgb(roles.accent),
        "ForegroundNormal": rgb(roles.highlight_text),
        "ForegroundActive": rgb(roles.highlight_text),
        "ForegroundInactive": rgb(roles.highlight_text),
        "ForegroundLink": rgb(roles.highlight_text),
        "ForegroundVisited": rgb(roles.highlight_text),
        "ForegroundNegative": rgb(roles.highlight_text),
        "ForegroundNeutral": rgb(roles.highlight_text),
        "ForegroundPositive": rgb(roles.highlight_text),
        "DecorationFocus": rgb(roles.accent),
        "DecorationHover": rgb(roles.hover),
    }
    return {
        "Colors:Window": {
            "BackgroundNormal": rgb(roles.window_surface),
            "BackgroundAlternate": rgb(alternate_surface),
            "ForegroundNormal": rgb(roles.window_text),
            **shared,
        },
        "Colors:View": {
            "BackgroundNormal": rgb(roles.base_surface),
            "BackgroundAlternate": rgb(alternate_surface),
            "ForegroundNormal": rgb(roles.text),
            **shared,
        },
        "Colors:Button": {
            "BackgroundNormal": rgb(roles.button_surface),
            "BackgroundAlternate": rgb(alternate_surface),
            "ForegroundNormal": rgb(roles.button_text),
            **shared,
        },
        "Colors:Selection": selection,
        "Colors:Tooltip": {
            "BackgroundNormal": rgb(roles.tooltip_surface),
            "BackgroundAlternate": rgb(roles.tooltip_surface),
            "ForegroundNormal": rgb(roles.tooltip_text),
            **shared,
        },
        "Colors:Header": {
            "BackgroundNormal": rgb(roles.button_surface),
            "BackgroundAlternate": rgb(alternate_surface),
            "ForegroundNormal": rgb(roles.button_text),
            **shared,
        },
        "Colors:Complementary": {
            "BackgroundNormal": rgb(roles.window_surface),
            "BackgroundAlternate": rgb(alternate_surface),
            "ForegroundNormal": rgb(roles.window_text),
            **shared,
        },
        "WM": {
            "activeBackground": rgb(roles.accent),
            "activeBlend": rgb(roles.accent),
            "activeForeground": rgb(roles.highlight_text),
            "inactiveBackground": rgb(roles.button_surface),
            "inactiveBlend": rgb(roles.button_surface),
            "inactiveForeground": rgb(roles.disabled_text),
        },
    }


def render_kde(roles):
    effects = {
        "ColorEffects:Disabled": {
            "Color": "112,111,110",
            "ColorAmount": "0",
            "ColorEffect": "0",
            "ContrastAmount": "0.25",
            "ContrastEffect": "1",
            "IntensityAmount": "0",
            "IntensityEffect": "0",
        },
        "ColorEffects:Inactive": {
            "ChangeSelectionColor": "true",
            "Color": "112,111,110",
            "ColorAmount": "0.5",
            "ColorEffect": "1",
            "ContrastAmount": "0.1",
            "ContrastEffect": "2",
            "Enable": "true",
            "IntensityAmount": "0.1",
            "IntensityEffect": "2",
        },
    }
    lines = [
        "[General]\nName=Pywal\nColorScheme=Pywal\n",
        "Description=Generated by render/qtct\nshadeSortColumn=true\n\n",
        "[KDE]\ncontrast=0\n\n",
    ]
    for section, values in effects.items():
        lines.append(f"[{section}]\n")
        for key, value in values.items():
            lines.append(f"{key}={value}\n")
        lines.append("\n")
    for section, values in kde_sections(roles).items():
        lines.append(f"[{section}]\n")
        for key, value in values.items():
            lines.append(f"{key}={value}\n")
        lines.append("\n")
    return "".join(lines)


def qt_palettes(roles):
    direction = 1 if roles.is_dark else -1
    alternate_surface = roles.alternate_surface or shade(roles.bg, 0.06 * direction)
    light = roles.light or shade(roles.button_surface, 0.35)
    mid_light = roles.mid_light or shade(roles.button_surface, 0.18)
    dark = roles.dark or shade(roles.button_surface, -0.35)
    mid = roles.mid or shade(roles.button_surface, -0.18)
    shadow = roles.shadow or shade(roles.bg, -0.60)

    # QPalette role order used by qtct: WindowText, Button, Light, Midlight,
    # Dark, Mid, Text, BrightText, ButtonText, Base, Window, Shadow, Highlight,
    # HighlightedText, Link, LinkVisited, AlternateBase, NoRole, ToolTipBase,
    # ToolTipText, PlaceholderText.
    active = [
        roles.window_text,
        roles.button_surface,
        light,
        mid_light,
        dark,
        mid,
        roles.text,
        roles.bright_text,
        roles.button_text,
        roles.base_surface,
        roles.window_surface,
        shadow,
        roles.accent,
        roles.highlight_text,
        roles.link,
        roles.link_visited,
        alternate_surface,
        roles.text,
        roles.tooltip_surface,
        roles.tooltip_text,
        roles.disabled_text,
    ]
    disabled = active.copy()
    for index in (0, 6, 7, 8, 13, 14, 15, 17, 19, 20):
        disabled[index] = roles.disabled_text
    inactive = active.copy()
    for index in (0, 6, 8, 17, 19, 20):
        inactive[index] = roles.disabled_text
    inactive[12] = roles.inactive_accent
    inactive[13] = roles.inactive_highlight_text
    return active, disabled, inactive


def render_qtct(roles):
    active, disabled, inactive = qt_palettes(roles)
    return (
        "[ColorScheme]\n"
        f"active_colors={qtct_line(active[:-1])}, {argb(active[-1], '80')}\n"
        f"disabled_colors={qtct_line(disabled[:-1])}, {argb(disabled[-1], '80')}\n"
        f"inactive_colors={qtct_line(inactive[:-1])}, {argb(inactive[-1], '80')}\n"
    )


def main():
    if not PALETTE.is_file():
        print(f"render/qtct: missing {PALETTE}", file=sys.stderr)
        sys.exit(1)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    palette = json.loads(PALETTE.read_text())
    pack_kvconfig, pack_colors_map = pack_role_files(palette)
    cache_key = renderer_hash(pack_kvconfig, pack_colors_map)
    if cache_hit("qtct", cache_key) and KDE_FILE.exists() and QTCT_FILE.exists():
        return

    roles = resolve_roles(palette, pack_kvconfig, pack_colors_map)
    atomic_write(KDE_FILE, render_kde(roles))
    atomic_write(QTCT_FILE, render_qtct(roles))
    cache_store("qtct", cache_key)


if __name__ == "__main__":
    main()
