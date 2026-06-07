#!/usr/bin/env python3
# Renderer: KColorScheme palette (~/.local/share/color-schemes/Pywal.colors).

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
OUT_FILE = OUT_DIR / "Pywal.colors"
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

    if cache_hit("qtct", h) and OUT_FILE.exists():
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
    link = roles.link
    link_visited = roles.link_visited
    highlight_text = roles.highlight_text
    colors = roles.colors

    d = 1 if roles.is_dark else -1
    bg_alt = shade(bg, 0.06 * d)
    bg_button = roles.button_surface
    bg_tooltip = shade(bg, 0.10 * d)
    fg_dim = shade(fg, 0.18 * -d)

    def rgb(c):
        r, g, b = (int(c.lstrip("#")[i:i+2], 16) for i in (0, 2, 4))
        return f"{r},{g},{b}"

    shared = {
        "ForegroundActive": rgb(accent),
        "ForegroundInactive": rgb(fg_dim),
        "ForegroundLink": rgb(link),
        "ForegroundVisited": rgb(link_visited),
        "ForegroundNegative": rgb(colors.get("color1", accent)),
        "ForegroundNeutral":  rgb(colors.get("color3", accent)),
        "ForegroundPositive": rgb(colors.get("color2", accent)),
        "DecorationFocus": rgb(accent),
        "DecorationHover": rgb(hover),
    }
    sections = {
        "Colors:Window":      {"BackgroundNormal": rgb(bg),       "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg), **shared},
        "Colors:View":        {"BackgroundNormal": rgb(bg),       "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg), **shared},
        "Colors:Button":      {"BackgroundNormal": rgb(bg_button),"BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg), **shared},
        "Colors:Selection":   {"BackgroundNormal": rgb(accent),   "BackgroundAlternate": rgb(accent),
                               "ForegroundNormal": rgb(highlight_text), "ForegroundActive": rgb(highlight_text),
                               "ForegroundInactive": rgb(highlight_text), "ForegroundLink": rgb(highlight_text),
                               "ForegroundVisited": rgb(highlight_text), "ForegroundNegative": rgb(highlight_text),
                               "ForegroundNeutral": rgb(highlight_text), "ForegroundPositive": rgb(highlight_text),
                               "DecorationFocus": rgb(accent), "DecorationHover": rgb(hover)},
        "Colors:Tooltip":     {"BackgroundNormal": rgb(bg_tooltip),"BackgroundAlternate": rgb(bg_alt),   "ForegroundNormal": rgb(fg), **shared},
        "Colors:Header":      {"BackgroundNormal": rgb(bg),       "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg), **shared},
        "Colors:Complementary":{"BackgroundNormal": rgb(bg),      "BackgroundAlternate": rgb(bg_alt),    "ForegroundNormal": rgb(fg), **shared},
        "WM": {"activeBackground": rgb(accent), "activeBlend": rgb(accent), "activeForeground": rgb(highlight_text),
               "inactiveBackground": rgb(bg_button), "inactiveBlend": rgb(bg_button), "inactiveForeground": rgb(fg_dim)},
    }
    effects = {
        "ColorEffects:Disabled": {"Color":"112,111,110","ColorAmount":"0","ColorEffect":"0","ContrastAmount":"0.25","ContrastEffect":"1","IntensityAmount":"0","IntensityEffect":"0"},
        "ColorEffects:Inactive": {"ChangeSelectionColor":"true","Color":"112,111,110","ColorAmount":"0.5","ColorEffect":"1","ContrastAmount":"0.1","ContrastEffect":"2","Enable":"true","IntensityAmount":"0.1","IntensityEffect":"2"},
    }

    fd, tmp_path = tempfile.mkstemp(dir=str(OUT_DIR), prefix=".Pywal.colors.")
    tmp = Path(tmp_path)
    try:
        with os.fdopen(fd, "w") as f:
            f.write("[General]\nName=Pywal\nColorScheme=Pywal\n")
            f.write("Description=Generated by render/qtct\nshadeSortColumn=true\n\n")
            f.write("[KDE]\ncontrast=0\n\n")
            for s, vs in effects.items():
                f.write(f"[{s}]\n")
                for k, v in vs.items(): f.write(f"{k}={v}\n")
                f.write("\n")
            for s, vs in sections.items():
                f.write(f"[{s}]\n")
                for k, v in vs.items(): f.write(f"{k}={v}\n")
                f.write("\n")
        os.replace(tmp, OUT_FILE)
    finally:
        if tmp.exists():
            try: tmp.unlink()
            except FileNotFoundError: pass

    cache_store("qtct", h)

if __name__ == "__main__":
    main()
