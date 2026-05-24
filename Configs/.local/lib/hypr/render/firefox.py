#!/usr/bin/env python3
# Renderer: Firefox userChrome.css across all profiles.
# Substitutes ~/.config/wal/templates/firefox-userChrome.css against the active
# palette + derived firefox roles. Then injects (between markers) into each
# profile's chrome/userChrome.css and ensures user.js enables custom chrome.

import configparser
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store

PALETTE = Path(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
               os.environ.get("HYPR_STATE_HOME",
                              os.path.expanduser("~/.local/state/hypr")) + "/active-palette.json")
TEMPLATE = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "wal" / "templates" / "firefox-userChrome.css"
FIREFOX_ROOT = Path(os.environ.get("FIREFOX_ROOT", Path.home() / ".mozilla" / "firefox"))
OUT_DIR = Path(os.environ.get("HYPR_CACHE_HOME", os.path.expanduser("~/.cache/hypr"))) / "render" / "firefox"
OUT_FILE = OUT_DIR / "userChrome.css"
MARKER_START = "/* BEGIN HYPR WAL FIREFOX USERCHROME */"
MARKER_END = "/* END HYPR WAL FIREFOX USERCHROME */"
PREF = "toolkit.legacyUserProfileCustomizations.stylesheets"
APP = "firefox"

def parse_hex(v):
    v = v.lstrip("#")
    if len(v) != 6: return None
    try:
        return tuple(int(v[i:i+2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        return None

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

def luminance(v):
    rgb = parse_hex(v)
    if rgb is None: return 0
    r, g, b = (srgb_to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

def hex_from(rgb):
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02X}" for c in rgb)

def mix(a, b, w):
    ra, rb = parse_hex(a), parse_hex(b)
    if ra is None: return b
    if rb is None: return a
    w2 = 1 - w
    return hex_from(tuple(ra[i] * w + rb[i] * w2 for i in range(3)))

def choose_text(bg, fg, alt):
    return fg if contrast(bg, fg) >= contrast(bg, alt) else alt

def firefox_roles(bg, fg, colors):
    accent = colors.get("color4", fg)
    light = luminance(bg) > 0.45
    if light:
        toolbar_bg = mix(bg, fg, 0.94)
        field_bg = bg
        field_focus_bg = bg
        field_border = mix(bg, fg, 0.78)
        tab_bg = bg
        tab_hover_bg = mix(bg, fg, 0.86)
        panel_bg = bg
        panel_border = mix(bg, fg, 0.84)
        highlight_bg = mix(bg, accent, 0.62)
        button_hover = mix(bg, fg, 0.88)
        button_active = mix(bg, fg, 0.78)
    else:
        toolbar_bg = bg
        field_bg = mix(bg, fg, 0.86)
        field_focus_bg = mix(bg, fg, 0.82)
        field_border = mix(bg, fg, 0.66)
        tab_bg = mix(bg, fg, 0.78)
        tab_hover_bg = mix(bg, fg, 0.88)
        panel_bg = mix(bg, fg, 0.80)
        panel_border = mix(bg, fg, 0.66)
        highlight_bg = mix(bg, accent, 0.55)
        button_hover = mix(bg, fg, 0.88)
        button_active = mix(bg, fg, 0.76)
    return {
        "color_scheme": "light" if light else "dark",
        "toolbar_bg": toolbar_bg, "toolbar_fg": fg,
        "field_bg": field_bg, "field_fg": fg, "field_border": field_border, "field_focus_bg": field_focus_bg,
        "tab_bg": tab_bg, "tab_fg": choose_text(tab_bg, fg, bg), "tab_hover_bg": tab_hover_bg, "tab_outline": panel_border,
        "panel_bg": panel_bg, "panel_fg": fg, "panel_border": panel_border,
        "highlight_bg": highlight_bg, "highlight_fg": choose_text(highlight_bg, fg, bg),
        "sidebar_bg": bg, "sidebar_fg": fg,
        "button_hover": button_hover, "button_active": button_active,
        "outline": accent,
    }

def render_template(template: str, palette: dict) -> str:
    mapping = {"background": palette["bg"], "foreground": palette["fg"]}
    mapping["background.strip"] = palette["bg"].lstrip("#")
    mapping["foreground.strip"] = palette["fg"].lstrip("#")
    colors = {f"color{i}": c for i, c in enumerate(palette["colors"])}
    for k, v in colors.items():
        mapping[k] = v
        mapping[f"{k}.strip"] = v.lstrip("#")
    for role, value in firefox_roles(palette["bg"], palette["fg"], colors).items():
        mapping[f"firefox.{role}"] = value
        mapping[f"firefox.{role}.strip"] = value.lstrip("#")

    out = re.sub(r"\{([A-Za-z0-9_.-]+)\}",
                 lambda m: mapping.get(m.group(1), m.group(0)),
                 template)
    return out.replace("{{", "{").replace("}}", "}")

def list_profiles():
    profiles_ini = FIREFOX_ROOT / "profiles.ini"
    if profiles_ini.is_file():
        cfg = configparser.ConfigParser()
        cfg.read(profiles_ini)
        seen = set()
        for s in cfg.sections():
            if not s.startswith("Profile"): continue
            raw = cfg[s].get("Path", "").strip()
            if not raw: continue
            p = Path(raw)
            if cfg[s].get("IsRelative", "1").strip() != "0":
                p = FIREFOX_ROOT / p
            p = p.expanduser()
            if p.is_dir():
                rp = str(p.resolve())
                if rp not in seen:
                    seen.add(rp)
                    yield Path(rp)
    else:
        for p in FIREFOX_ROOT.glob("*.default*"):
            if p.is_dir(): yield p

def inject_marker(profile: Path, snippet: str):
    chrome_dir = profile / "chrome"
    chrome_dir.mkdir(parents=True, exist_ok=True)
    target = chrome_dir / "userChrome.css"
    existing = ""
    if target.is_file():
        # Strip prior marker block
        keep = []
        skip = False
        for line in target.read_text().splitlines():
            if line == MARKER_START: skip = True; continue
            if line == MARKER_END:   skip = False; continue
            if not skip: keep.append(line)
        existing = "\n".join(keep).rstrip("\n")
    content = MARKER_START + "\n" + snippet.rstrip("\n") + "\n" + MARKER_END + "\n\n"
    if existing:
        content += existing + "\n"
    atomic_write(target, content)

def ensure_pref(profile: Path):
    target = profile / "user.js"
    pref_line = f'user_pref("{PREF}", true);\n'
    if not target.is_file():
        atomic_write(target, pref_line)
        return
    lines = target.read_text().splitlines(keepends=True)
    done = False
    out = []
    for line in lines:
        if re.match(rf'^user_pref\("{re.escape(PREF)}",', line):
            if not done:
                out.append(pref_line); done = True
            continue
        out.append(line)
    if not done: out.append(pref_line)
    atomic_write(target, "".join(out))

def main():
    if not PALETTE.is_file():
        sys.exit(f"render/firefox: missing {PALETTE}")
    if not TEMPLATE.is_file():
        # No template = nothing to do (legitimately optional)
        return
    if not FIREFOX_ROOT.is_dir():
        return

    palette = json.loads(PALETTE.read_text())
    profiles = list(list_profiles())
    if not profiles:
        return

    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    hasher.update(TEMPLATE.read_bytes())
    hasher.update(Path(__file__).read_bytes())
    for p in profiles: hasher.update(str(p).encode())
    h = hasher.hexdigest()[:16]

    if cache_hit(APP, h) and OUT_FILE.exists() and all(
            (p / "chrome" / "userChrome.css").exists() for p in profiles):
        return

    rendered = render_template(TEMPLATE.read_text(), palette)
    atomic_write(OUT_FILE, rendered)
    for p in profiles:
        inject_marker(p, rendered)
        ensure_pref(p)

    cache_store(APP, h)

if __name__ == "__main__":
    main()
