#!/usr/bin/env python3
# Renderer: dunst dunstrc (palette overlay + Hyprland-derived layout + category rules).
# Writes ~/.config/dunst/dunstrc and reloads dunst.

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
CONF_DIR     = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "dunst"
BASE_CONF    = CONF_DIR / "dunst.conf"
DUNST_CONF   = CONF_DIR / "dunstrc"
THEMES_DIR   = Path(os.environ.get("HYPR_CONFIG_HOME", os.path.expanduser("~/.config/hypr"))) / "themes"
THEME_CONF   = THEMES_DIR / "theme.meta"
WAYBAR_CONF  = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "waybar" / "config.jsonc"
OUT_DIR      = Path(os.environ.get("HYPR_CACHE_HOME", os.path.expanduser("~/.cache/hypr"))) / "render" / "dunst"
OUT_FILE     = OUT_DIR / "dunstrc"

APP = "dunst"

def first(*vals):
    for v in vals:
        if v: return v
    return ""

def with_alpha(color, alpha_hex):
    c = color.lstrip("#")
    a = alpha_hex.lstrip("#").upper()
    if len(c) == 8: return "#" + c[:6].upper() + a
    if len(c) == 6: return "#" + c.upper() + a
    return "#" + c

_VAR_RX = re.compile(r"^\s*\$(\S+?)\s*=\s*(.*?)(?:\s*#.*)?$")
_METRIC_RX = re.compile(r"^\s*([^$\s]\S*)\s*=\s*(\S+)")
_theme_cache = None

def _theme_cache_get():
    global _theme_cache
    if _theme_cache is not None:
        return _theme_cache
    vars_d, metrics_d = {}, {}
    if THEME_CONF.is_file():
        for line in THEME_CONF.read_text().splitlines():
            m = _VAR_RX.match(line)
            if m:
                vars_d[m.group(1)] = m.group(2).strip().strip('"').strip("'")
                continue
            m = _METRIC_RX.match(line)
            if m:
                metrics_d[m.group(1)] = m.group(2)
    _theme_cache = (vars_d, metrics_d)
    return _theme_cache

def read_theme_var(key):
    return _theme_cache_get()[0].get(key, "")

def read_theme_metric(key):
    return _theme_cache_get()[1].get(key, "")

def read_hypr_metric(opt):
    try:
        out = subprocess.run(["hyprctl", "-j", "getoption", opt],
                             capture_output=True, text=True, check=True).stdout
        v = json.loads(out).get("int", "")
        return str(v) if v != "" else ""
    except Exception:
        return ""

def resolve_metric(key, opt, default):
    return read_theme_metric(key) or read_hypr_metric(opt) or default

def waybar_position():
    if WAYBAR_CONF.is_file():
        try:
            for line in WAYBAR_CONF.read_text().splitlines():
                m = re.search(r'"position"\s*:\s*"([^"]*)"', line)
                if m: return m.group(1)
        except Exception:
            pass
    return "right"

def load_pack_overrides(pack_name):
    """Return dict of name → #hex from pack's dunst.theme (@define-color lines)."""
    overrides = {}
    if not pack_name: return overrides
    f = THEMES_DIR / pack_name / "dunst.theme"
    if not f.is_file(): return overrides
    rx = re.compile(r"^\s*@define-color\s+(\S+)\s+(#[0-9A-Fa-f]{6,8})\s*;?\s*$")
    for line in f.read_text().splitlines():
        m = rx.match(line)
        if m: overrides[m.group(1)] = m.group(2)
    return overrides

def ensure_base():
    if BASE_CONF.is_file(): return
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    if DUNST_CONF.is_file():
        BASE_CONF.write_text(DUNST_CONF.read_text())
    elif Path("/etc/dunst/dunstrc").is_file():
        BASE_CONF.write_text(Path("/etc/dunst/dunstrc").read_text())
    else:
        BASE_CONF.write_text("[global]\n    monitor = 0\n")

def reload_dunst():
    try:
        if subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "dunst"],
                          stdout=subprocess.DEVNULL).returncode != 0:
            return
    except FileNotFoundError:
        return
    if subprocess.run(["dunstctl", "reload"], stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode != 0:
        subprocess.run(["pkill", "-HUP", "-x", "dunst"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def main():
    if not PALETTE.is_file():
        sys.exit(f"render/dunst: missing {PALETTE}")
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ensure_base()

    p = json.loads(PALETTE.read_text())
    bg = p["bg"]; fg = p["fg"]
    c = p["colors"]
    pack = p.get("source", "").removeprefix("theme:") if p.get("source", "").startswith("theme:") else ""
    overrides = load_pack_overrides(pack)
    def role(name, fallback): return overrides.get(name, fallback)

    bg_primary    = role("bg-primary",     first(bg, c[0], "#1e1e2e"))
    bg_secondary  = role("bg-secondary",   bg_primary)
    bg_tertiary   = role("bg-tertiary",    bg_primary)
    fg_primary    = role("fg-primary",     first(fg, c[15], "#f8f8f2"))
    fg_secondary  = role("fg-secondary",   fg_primary)
    border_primary   = role("border-primary",   first(c[4], c[12], "#6272a4"))
    border_secondary = role("border-secondary", first(c[8], border_primary, "#44475a"))
    accent_red    = role("accent-red",    first(c[1], c[9],  "#ff5555"))
    accent_green  = role("accent-green",  first(c[2], c[10], border_primary, "#50fa7b"))
    accent_yellow = role("accent-yellow", first(c[3], c[11], border_primary, "#f1fa8c"))
    accent_blue   = role("accent-blue",   first(c[4], c[12], border_primary, "#8be9fd"))
    accent_purple = role("accent-purple", first(c[5], c[13], accent_blue,   "#bd93f9"))
    accent_aqua   = role("accent-aqua",   first(c[6], c[14], accent_blue,   "#8be9fd"))
    accent_orange = role("accent-orange", first(c[11], c[3], accent_red,    "#ffb86c"))
    gray          = role("gray",          first(c[8], border_secondary,    "#6272a4"))

    bg_critical = accent_red
    fg_critical = fg_primary

    bg_low_render      = with_alpha(bg_secondary, "80")
    bg_normal_render   = with_alpha(bg_primary,   "80")
    bg_category_render = with_alpha(bg_tertiary,  "80")
    bg_critical_render = with_alpha(bg_critical,  "80")
    fg_low_render      = with_alpha(fg_secondary, "E6")
    fg_normal_render   = with_alpha(fg_primary,   "E6")
    fg_category_render = with_alpha(fg_primary,   "E6")
    fg_critical_render = fg_critical
    frame_low_render    = with_alpha(border_secondary, "33")
    frame_normal_render = with_alpha(border_primary,   "55")
    frame_critical      = accent_red
    progress_fg         = accent_blue
    cat_email   = with_alpha(accent_blue,   "55")
    cat_chat    = with_alpha(accent_aqua,   "55")
    cat_warning = with_alpha(accent_yellow, "55")
    cat_error   = with_alpha(accent_red,    "55")
    cat_network = with_alpha(accent_blue,   "55")
    cat_battery = with_alpha(accent_orange, "55")
    cat_update  = with_alpha(accent_green,  "55")
    cat_music   = with_alpha(accent_purple, "55")
    cat_volume  = with_alpha(gray,          "55")

    # Layout metrics
    rounding    = resolve_metric("rounding",    "decoration:rounding", "5")
    gaps_in     = resolve_metric("gaps_in",     "general:gaps_in",     "5")
    gaps_out    = resolve_metric("gaps_out",    "general:gaps_out",    "6")
    border_size = resolve_metric("border_size", "general:border_size", "2")
    try: gap_size = int(gaps_in) * 2
    except ValueError: gap_size = 10
    try: edge_padding = int(gaps_out) * 2 + int(border_size)
    except ValueError: edge_padding = 14

    pos = waybar_position()
    origin = {"left": "top-left", "bottom": "bottom-right", "top": "top-right"}.get(pos, "top-right")

    # Font
    icon_theme = first(os.environ.get("ICON_THEME"), os.environ.get("GTK_ICON"), read_theme_var("ICON_THEME"))
    if not icon_theme:
        try:
            out = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
                                 capture_output=True, text=True).stdout.strip().strip("'")
            icon_theme = out
        except FileNotFoundError:
            pass
    icon_theme = icon_theme or "hicolor"

    notification_font = first(os.environ.get("NOTIFICATION_FONT"), read_theme_var("FONT"))
    font_size_env = os.environ.get("FONT_SIZE", "")
    notification_font_size = font_size_env if font_size_env.isdigit() else (read_theme_var("FONT_SIZE") or "10")
    if not notification_font_size.isdigit(): notification_font_size = "10"
    font_line = f"    font = {notification_font} {notification_font_size}" if notification_font else ""

    # Cache key
    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    if BASE_CONF.is_file(): hasher.update(BASE_CONF.read_bytes())
    if pack:
        dt = THEMES_DIR / pack / "dunst.theme"
        if dt.is_file(): hasher.update(dt.read_bytes())
    for s in (rounding, gaps_in, border_size, origin, str(edge_padding), notification_font,
              notification_font_size, icon_theme, bg_normal_render, fg_normal_render,
              frame_normal_render, progress_fg):
        hasher.update(str(s).encode())
    hasher.update(Path(__file__).read_bytes())
    h = hasher.hexdigest()[:16]

    if cache_hit(APP, h) and DUNST_CONF.exists() and OUT_FILE.exists():
        return

    base = BASE_CONF.read_text() if BASE_CONF.is_file() else "[global]\n    monitor = 0\n"

    def category_rule(section, category, color):
        out = []
        for urgency in ("low", "normal"):
            out.append(f"""
[category_{section}_{urgency}]
    category = {category}
    msg_urgency = {urgency}
    background = "{bg_category_render}"
    foreground = "{fg_category_render}"
    frame_color = "{color}"
    highlight = "{color}"
    timeout = 2""")
        return "".join(out)

    try: corner_radius = int(rounding) * 3 // 2
    except ValueError: corner_radius = 7

    content = f"""# WARNING: This file is auto-generated by render/dunst.
# DO NOT edit manually.
# Edit '{BASE_CONF}' to change the base configuration.

{base}

# Dynamic overrides generated from active palette + Hyprland state.
[global]
    monitor = 0
    origin = {origin}
    offset = ({edge_padding},{edge_padding})
    gap_size = {gap_size}
    frame_width = {border_size}
    progress_bar_corner_radius = {rounding}
    icon_theme = "{icon_theme}"
    corner_radius = {corner_radius}
    icon_corner_radius = {rounding}
{font_line}

[urgency_low]
    background = "{bg_low_render}"
    foreground = "{fg_low_render}"
    frame_color = "{frame_low_render}"
    highlight = "{progress_fg}"
    timeout = 2

[urgency_normal]
    background = "{bg_normal_render}"
    foreground = "{fg_normal_render}"
    frame_color = "{frame_normal_render}"
    highlight = "{progress_fg}"
    timeout = 2

[urgency_critical]
    background = "{bg_critical_render}"
    foreground = "{fg_critical_render}"
    frame_color = "{frame_critical}"
    highlight = "{frame_critical}"
    timeout = 0
{category_rule("email",   "email",   cat_email)}
{category_rule("chat",    "chat",    cat_chat)}
{category_rule("warning", "warning", cat_warning)}
{category_rule("error",   "error",   cat_error)}
{category_rule("network", "network", cat_network)}
{category_rule("battery", "battery", cat_battery)}
{category_rule("update",  "update",  cat_update)}
{category_rule("music",   "music",   cat_music)}
{category_rule("volume",  "volume",  cat_volume)}
"""

    # Write to both render cache + live dunstrc (dunst reads dunstrc directly)
    for target in (OUT_FILE, DUNST_CONF):
        atomic_write(target, content)

    cache_store(APP, h)
    reload_dunst()

if __name__ == "__main__":
    main()
