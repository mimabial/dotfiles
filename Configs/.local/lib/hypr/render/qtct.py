#!/usr/bin/env python3
import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store
from _roles import QtRoles, hex_to_rgb, palette_to_pywal, shade
from _shell import shell_files

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


def rgb(color):
    red, green, blue = hex_to_rgb(color)
    return f"{red},{green},{blue}"


def renderer_hash(shell_kvconfig, shell_colors_map):
    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    for path in (
        shell_kvconfig,
        shell_colors_map,
        Path(__file__),
        Path(__file__).with_name("_roles.py"),
    ):
        if path and path.is_file():
            hasher.update(path.read_bytes())
    return hasher.hexdigest()[:16]


def resolve_roles(palette, shell_kvconfig, shell_colors_map):
    return QtRoles(
        pywal=palette_to_pywal(palette),
        kvconfig_path=str(shell_kvconfig) if shell_kvconfig else None,
        colors_map_path=str(shell_colors_map) if shell_colors_map else None,
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
            "BackgroundNormal": rgb(roles.window_surface),
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


def main():
    if not PALETTE.is_file():
        print(f"render/qtct: missing {PALETTE}", file=sys.stderr)
        sys.exit(1)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    palette = json.loads(PALETTE.read_text())
    shell_kvconfig, shell_colors_map = shell_files(palette)
    cache_key = renderer_hash(shell_kvconfig, shell_colors_map)
    if cache_hit("qtct", cache_key) and KDE_FILE.exists():
        return

    roles = resolve_roles(palette, shell_kvconfig, shell_colors_map)
    atomic_write(KDE_FILE, render_kde(roles))
    cache_store("qtct", cache_key)


if __name__ == "__main__":
    main()
