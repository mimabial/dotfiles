#!/usr/bin/env python3
# Renderer: KColorScheme palette (~/.local/share/color-schemes/Pywal.colors).
# Reads ~/.local/state/hypr/active-palette.json and the active theme pack's
# kvantum/kvconfig.theme + colors.map (when present) for role overrides.
# In theme mode, pack [GeneralColors] window.color / window.text.color win.

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PALETTE = Path(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
               os.environ.get("HYPR_STATE_HOME",
                              os.path.expanduser("~/.local/state/hypr")) + "/active-palette.json")
OUT_DIR = Path(os.environ.get("HYPR_CACHE_HOME",
                              os.path.expanduser("~/.cache/hypr"))) / "render" / "qtct"
OUT_FILE = OUT_DIR / "Pywal.colors"
THEMES_DIR = Path(os.environ.get("HYPR_CONFIG_HOME",
                                 os.path.expanduser("~/.config/hypr"))) / "themes"

def run(cmd, **kw):
    return subprocess.run(cmd, check=False, **kw)

def cache_hit(app, h):
    r = run(["render-cache", "hit?", app, h])
    return r.returncode == 0

def cache_store(app, h):
    run(["render-cache", "store", app, h])

def main():
    if not PALETTE.is_file():
        print(f"render/qtct: missing {PALETTE}", file=sys.stderr)
        sys.exit(1)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    palette = json.loads(PALETTE.read_text())
    bg = palette["bg"]
    fg = palette["fg"]
    colors = {f"color{i}": c for i, c in enumerate(palette["colors"])}
    src = palette.get("source", "")
    mode = palette.get("mode", "wallpaper")

    pack_kvconfig = pack_colors_map = None
    if mode == "theme" and src.startswith("theme:"):
        pack_dir = THEMES_DIR / src.removeprefix("theme:")
        kv = pack_dir / "kvantum" / "kvconfig.theme"
        cm = pack_dir / "kvantum" / "colors.map"
        if kv.is_file(): pack_kvconfig = kv
        if cm.is_file(): pack_colors_map = cm

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    for p in (pack_kvconfig, pack_colors_map, Path(__file__)):
        if p and p.is_file(): hasher.update(p.read_bytes())
    h = hasher.hexdigest()[:16]

    if cache_hit("qtct", h) and OUT_FILE.exists():
        return

    palette_full = {**colors, "background": bg, "foreground": fg}

    def general_color(key):
        if not pack_kvconfig: return None
        sec = re.search(r"(?ms)^\[GeneralColors\]\n(.*?)(?=^\[|\Z)", pack_kvconfig.read_text())
        if not sec: return None
        m = re.search(r"^" + re.escape(key) + r"\s*=\s*(#[0-9a-fA-F]{6})", sec.group(1), re.M)
        return m.group(1).lower() if m else None

    def resolve_role(key, default_var):
        target = general_color(key)
        if not target:
            return colors.get(default_var, fg)
        if mode == "theme":
            return target
        if pack_colors_map:
            for line in pack_colors_map.read_text().splitlines():
                line = line.strip()
                if "=" not in line: continue
                hex_part, _, var = line.partition("=")
                if hex_part.strip().lower() != target: continue
                return palette_full.get(var.strip(), target)
        return colors.get(default_var, fg)

    if mode == "theme":
        pack_bg = general_color("window.color")
        pack_fg = general_color("window.text.color") or general_color("text.color")
        if pack_bg: bg = pack_bg
        if pack_fg:
            fg = pack_fg
        elif pack_bg:
            def lum(h):
                h = h.lstrip("#"); r, g, b = (int(h[i:i+2], 16)/255 for i in (0, 2, 4))
                return 0.299*r + 0.587*g + 0.114*b
            fg = "#e0e0e0" if lum(pack_bg) < 0.5 else "#202020"

    accent = resolve_role("highlight.color", "color4")
    link_visited = resolve_role("link.visited.color", "color5")
    hover = colors.get("color12", accent)

    def hex_to_rgb(c):
        c = c.lstrip("#")
        return tuple(int(c[i:i+2], 16) for i in (0, 2, 4))
    def rgb(c): return ",".join(str(x) for x in hex_to_rgb(c))
    def lum(c): r,g,b = (x/255 for x in hex_to_rgb(c)); return 0.299*r+0.587*g+0.114*b
    def shade(c, amount):
        r, g, b = hex_to_rgb(c)
        if amount >= 0:
            r = round(r + (255-r)*amount); g = round(g + (255-g)*amount); b = round(b + (255-b)*amount)
        else:
            r = round(r*(1+amount)); g = round(g*(1+amount)); b = round(b*(1+amount))
        return f"#{r:02x}{g:02x}{b:02x}"

    is_dark = lum(bg) < 0.5
    d = 1 if is_dark else -1
    bg_alt = shade(bg, 0.06*d)
    bg_button = shade(bg, 0.12*d)
    bg_tooltip = shade(bg, 0.10*d)
    fg_dim = shade(fg, 0.18*-d)
    highlight_text = bg if abs(lum(fg)-lum(accent)) < abs(lum(bg)-lum(accent)) else fg

    shared = {
        "ForegroundActive": rgb(accent),
        "ForegroundInactive": rgb(fg_dim),
        "ForegroundLink": rgb(accent),
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
