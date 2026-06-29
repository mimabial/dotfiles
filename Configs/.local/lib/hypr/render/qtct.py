#!/usr/bin/env python3
# Renderer: KDE KColorScheme + qt6ct palette generated from shared Qt roles.

import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import cache_hit, cache_store
from _roles import QtRoles, shade

PALETTE = Path(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
               os.environ.get("HYPR_STATE_HOME",
                              os.path.expanduser("~/.local/state/hypr")) + "/active-palette.json")
OUT_DIR = Path(os.environ.get("HYPR_CACHE_HOME",
                              os.path.expanduser("~/.cache/hypr"))) / "render" / "qtct"
KDE_FILE = OUT_DIR / "Pywal.colors"
QTCT_FILE = OUT_DIR / "pywal16.conf"
THEMES_DIR = Path(os.environ.get("HYPR_CONFIG_HOME",
                                 os.path.expanduser("~/.config/hypr"))) / "themes"


def main():
    if not PALETTE.is_file():
        print(f"render/qtct: missing {PALETTE}", file=sys.stderr)
        sys.exit(1)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    palette = json.loads(PALETTE.read_text())
    src = palette.get("source", "")
    mode = palette.get("mode", "wallpaper")
    theme_mode = mode == "theme"

    pack_kvconfig = pack_colors_map = None
    if theme_mode and src.startswith("theme:"):
        pack_dir = THEMES_DIR / src.removeprefix("theme:")
        kv = pack_dir / "kvantum" / "kvconfig.theme"
        cm = pack_dir / "kvantum" / "colors.map"
        if kv.is_file(): pack_kvconfig = kv
        if cm.is_file(): pack_colors_map = cm

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    for p in (pack_kvconfig, pack_colors_map, Path(__file__), Path(__file__).with_name("_roles.py")):
        if p and p.is_file(): hasher.update(p.read_bytes())
    h = hasher.hexdigest()[:16]

    if cache_hit("qtct", h) and KDE_FILE.exists() and QTCT_FILE.exists():
        return

    pywal = {
        "special": {"background": palette["bg"], "foreground": palette["fg"]},
        "colors": {f"color{i}": c for i, c in enumerate(palette["colors"])},
    }
    roles = QtRoles(
        pywal=pywal,
        theme_mode=theme_mode,
        kvconfig_path=str(pack_kvconfig) if pack_kvconfig else None,
        colors_map_path=str(pack_colors_map) if pack_colors_map else None,
    )

    bg, fg = roles.bg, roles.fg
    accent, hover = roles.accent, roles.hover
    inactive_accent = roles.inactive_accent
    link = roles.link
    link_visited = roles.link_visited
    highlight_text = roles.highlight_text
    inactive_highlight_text = roles.inactive_highlight_text
    colors = roles.colors

    d = 1 if roles.is_dark else -1
    bg_alt = roles.alternate_surface or shade(bg, 0.06 * d)
    bg_window = roles.window_surface
    bg_base = roles.base_surface
    bg_button = roles.button_surface
    bg_tooltip = roles.tooltip_surface
    fg_text = roles.text
    fg_window = roles.window_text
    fg_button = roles.button_text
    fg_tooltip = roles.tooltip_text
    fg_dim = roles.disabled_text

    def rgb(c):
        r, g, b = (int(c.lstrip("#")[i:i+2], 16) for i in (0, 2, 4))
        return f"{r},{g},{b}"

    def argb(c, alpha="ff"):
        return f"#{alpha}{c.lstrip('#').lower()}"

    def qtct_line(values):
        return ", ".join(argb(c) for c in values)

    def atomic_write(path, content):
        fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
        tmp = Path(tmp_path)
        try:
            with os.fdopen(fd, "w") as f:
                f.write(content)
            os.replace(tmp, path)
        finally:
            if tmp.exists():
                try: tmp.unlink()
                except FileNotFoundError: pass

    shared = {
        "ForegroundActive": rgb(accent),
        "ForegroundInactive": rgb(fg_dim),
        "ForegroundLink": rgb(link),
        "ForegroundVisited": rgb(link_visited),
        "ForegroundNegative": rgb(colors["color1"]),
        "ForegroundNeutral":  rgb(colors["color3"]),
        "ForegroundPositive": rgb(colors["color2"]),
        "DecorationFocus": rgb(accent),
        "DecorationHover": rgb(hover),
    }
    sections = {
        "Colors:Window":      {"BackgroundNormal": rgb(bg_window), "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg_window), **shared},
        "Colors:View":        {"BackgroundNormal": rgb(bg_base),   "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg_text), **shared},
        "Colors:Button":      {"BackgroundNormal": rgb(bg_button), "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg_button), **shared},
        "Colors:Selection":   {"BackgroundNormal": rgb(accent),   "BackgroundAlternate": rgb(accent),
                               "ForegroundNormal": rgb(highlight_text), "ForegroundActive": rgb(highlight_text),
                               "ForegroundInactive": rgb(highlight_text), "ForegroundLink": rgb(highlight_text),
                               "ForegroundVisited": rgb(highlight_text), "ForegroundNegative": rgb(highlight_text),
                               "ForegroundNeutral": rgb(highlight_text), "ForegroundPositive": rgb(highlight_text),
                               "DecorationFocus": rgb(accent), "DecorationHover": rgb(hover)},
        "Colors:Tooltip":     {"BackgroundNormal": rgb(bg_tooltip),"BackgroundAlternate": rgb(bg_tooltip), "ForegroundNormal": rgb(fg_tooltip), **shared},
        "Colors:Header":      {"BackgroundNormal": rgb(bg_button), "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg_button), **shared},
        "Colors:Complementary":{"BackgroundNormal": rgb(bg_window),"BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg_window), **shared},
        "WM": {"activeBackground": rgb(accent), "activeBlend": rgb(accent), "activeForeground": rgb(highlight_text),
               "inactiveBackground": rgb(bg_button), "inactiveBlend": rgb(bg_button), "inactiveForeground": rgb(fg_dim)},
    }
    effects = {
        "ColorEffects:Disabled": {"Color":"112,111,110","ColorAmount":"0","ColorEffect":"0","ContrastAmount":"0.25","ContrastEffect":"1","IntensityAmount":"0","IntensityEffect":"0"},
        "ColorEffects:Inactive": {"ChangeSelectionColor":"true","Color":"112,111,110","ColorAmount":"0.5","ColorEffect":"1","ContrastAmount":"0.1","ContrastEffect":"2","Enable":"true","IntensityAmount":"0.1","IntensityEffect":"2"},
    }

    kde_lines = []
    kde_lines.append("[General]\nName=Pywal\nColorScheme=Pywal\n")
    kde_lines.append("Description=Generated by render/qtct\nshadeSortColumn=true\n\n")
    kde_lines.append("[KDE]\ncontrast=0\n\n")
    for s, vs in effects.items():
        kde_lines.append(f"[{s}]\n")
        for k, v in vs.items():
            kde_lines.append(f"{k}={v}\n")
        kde_lines.append("\n")
    for s, vs in sections.items():
        kde_lines.append(f"[{s}]\n")
        for k, v in vs.items():
            kde_lines.append(f"{k}={v}\n")
        kde_lines.append("\n")
    atomic_write(KDE_FILE, "".join(kde_lines))

    light = roles.light or shade(bg_button, 0.35)
    mid_light = roles.mid_light or shade(bg_button, 0.18)
    dark = roles.dark or shade(bg_button, -0.35)
    mid = roles.mid or shade(bg_button, -0.18)
    shadow = roles.shadow or shade(bg, -0.60)
    bright_text = roles.bright_text

    # QPalette role order used by qtct: WindowText, Button, Light, Midlight,
    # Dark, Mid, Text, BrightText, ButtonText, Base, Window, Shadow, Highlight,
    # HighlightedText, Link, LinkVisited, AlternateBase, NoRole, ToolTipBase,
    # ToolTipText, PlaceholderText.
    active = [
        fg_window, bg_button, light, mid_light, dark, mid, fg_text, bright_text, fg_button,
        bg_base, bg_window, shadow, accent, highlight_text, link, link_visited, bg_alt,
        fg_text, bg_tooltip, fg_tooltip, fg_dim,
    ]
    disabled = active.copy()
    for i in (0, 6, 7, 8, 13, 14, 15, 17, 19, 20):
        disabled[i] = fg_dim
    inactive = active.copy()
    for i in (0, 6, 8, 17, 19, 20):
        inactive[i] = fg_dim
    inactive[12] = inactive_accent
    inactive[13] = inactive_highlight_text

    qtct_content = (
        "[ColorScheme]\n"
        f"active_colors={qtct_line(active[:-1])}, {argb(active[-1], '80')}\n"
        f"disabled_colors={qtct_line(disabled[:-1])}, {argb(disabled[-1], '80')}\n"
        f"inactive_colors={qtct_line(inactive[:-1])}, {argb(inactive[-1], '80')}\n"
    )
    atomic_write(QTCT_FILE, qtct_content)

    cache_store("qtct", h)

if __name__ == "__main__":
    main()
