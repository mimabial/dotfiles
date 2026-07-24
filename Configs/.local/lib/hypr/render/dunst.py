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

PALETTE = Path(
    sys.argv[1]
    if len(sys.argv) > 1 and sys.argv[1]
    else os.environ.get("HYPR_STATE_HOME", os.path.expanduser("~/.local/state/hypr"))
    + "/active-palette.json"
)
CONF_DIR = (
    Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "dunst"
)
BASE_CONF = CONF_DIR / "dunst.conf"
DUNST_CONF = CONF_DIR / "dunstrc"
THEMES_DIR = (
    Path(os.environ.get("HYPR_CONFIG_HOME", os.path.expanduser("~/.config/hypr")))
    / "themes"
)
THEME_CONF = THEMES_DIR / "theme.meta"
WAYBAR_CONF = (
    Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
    / "waybar"
    / "config.jsonc"
)
OUT_DIR = (
    Path(os.environ.get("HYPR_CACHE_HOME", os.path.expanduser("~/.cache/hypr")))
    / "render"
    / "dunst"
)
OUT_FILE = OUT_DIR / "dunstrc"
ROLES_FILE = OUT_DIR / "colors.conf"
WAL_TEMPLATES_DIR = (
    Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
    / "wal"
    / "templates"
)

APP = "dunst"


def first(*vals):
    for v in vals:
        if v:
            return v
    return ""


def with_alpha(color, alpha_hex):
    c = color.lstrip("#")
    a = alpha_hex.lstrip("#").upper()
    if len(c) == 8:
        return "#" + c[:6].upper() + a
    if len(c) == 6:
        return "#" + c.upper() + a
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


# Mirrors hypr_config_layer_files() / hypr_config_layer_cache_load() in
# core/common.sh: userfonts.lua, then theme.meta, then variables.meta defaults.
# First layer to define a key wins.
_LUA_VAR_RX = re.compile(r'^\s*vars\.set\("([^"]+)",\s*"([^"]*)"\)')
_layer_cache = None


def _layer_files():
    config_home = Path(
        os.environ.get("HYPR_CONFIG_HOME", os.path.expanduser("~/.config/hypr"))
    )
    data_home = Path(
        os.environ.get("HYPR_DATA_HOME", os.path.expanduser("~/.local/share/hypr"))
    )
    variables = data_home / "variables.meta"
    if not variables.is_file():
        variables = config_home / "variables.meta"
    return (config_home / "userfonts.lua", THEME_CONF, variables)


def _layer_cache_get():
    global _layer_cache
    if _layer_cache is not None:
        return _layer_cache
    vars_d = {}
    for path in _layer_files():
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            m = _LUA_VAR_RX.match(line)
            if m:
                key, value = m.group(1), m.group(2)
            else:
                m = _VAR_RX.match(line)
                if not m:
                    continue
                key, value = m.group(1), m.group(2).strip().strip('"').strip("'")
            if value and key not in vars_d:
                vars_d[key] = value
    _layer_cache = vars_d
    return _layer_cache


def read_layer_var(key):
    return _layer_cache_get().get(key, "")


def read_theme_metric(key):
    return _theme_cache_get()[1].get(key, "")


def read_hypr_metric(opt):
    try:
        out = subprocess.run(
            ["hyprctl", "-j", "getoption", opt],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
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
                if m:
                    return m.group(1)
        except Exception:
            pass
    return "right"


_DEFINE_COLOR_RX = re.compile(
    r"^\s*@define-color\s+(\S+)\s+(#[0-9A-Fa-f]{6,8})\s*;?\s*(?:/\*.*\*/\s*)?$"
)


def _parse_define_colors(text):
    overrides = {}
    for line in text.splitlines():
        m = _DEFINE_COLOR_RX.match(line)
        if m:
            overrides[m.group(1)] = m.group(2)
    return overrides


def load_pack_overrides(pack_name):
    """Return dict of name → #hex from pack's dunst.theme (@define-color lines)."""
    if not pack_name:
        return {}
    f = THEMES_DIR / pack_name / "dunst.theme"
    if not f.is_file():
        return {}
    return _parse_define_colors(f.read_text())


def dunst_template_layers(variant):
    layers = []
    for name in ("colors-dunst.theme", f"colors-dunst.{variant}.theme"):
        f = WAL_TEMPLATES_DIR / name
        if f.is_file():
            layers.append(f)
    return layers


def load_dunst_template(variant, bg, fg, colors):
    """Return dict of role → #hex from colors-dunst.theme (shared, optional) then
    colors-dunst.<variant>.theme (per-variant, wins), substituting the live pywal
    palette. Files are sparse: list only the roles you want to override."""
    subs = {"background": bg, "foreground": fg}
    for i, col in enumerate(colors):
        subs[f"color{i}"] = col
    merged = {}
    for f in dunst_template_layers(variant):
        text = f.read_text()
        for key, value in subs.items():
            text = text.replace("{" + key + "}", value)
        merged.update(_parse_define_colors(text))
    return merged


def ensure_base():
    if BASE_CONF.is_file():
        return
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    if DUNST_CONF.is_file():
        BASE_CONF.write_text(DUNST_CONF.read_text())
    elif Path("/etc/dunst/dunstrc").is_file():
        BASE_CONF.write_text(Path("/etc/dunst/dunstrc").read_text())
    else:
        BASE_CONF.write_text("[global]\n    monitor = 0\n")


def reload_dunst():
    try:
        if (
            subprocess.run(
                ["pgrep", "-u", str(os.getuid()), "-x", "dunst"],
                stdout=subprocess.DEVNULL,
            ).returncode
            != 0
        ):
            return
    except FileNotFoundError:
        return
    if (
        subprocess.run(
            ["dunstctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode
        != 0
    ):
        subprocess.run(
            ["pkill", "-HUP", "-x", "dunst"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    refresh_submap_hint()


def refresh_submap_hint():
    # The reload restyles only new notifications; a submap hint on screen
    # would keep the previous palette until the submap is re-entered.
    hint_script = (
        Path(__file__).resolve().parent.parent / "keybinds" / "submap-hint.sh"
    )
    if not hint_script.is_file():
        return
    try:
        subprocess.Popen(
            ["bash", str(hint_script), "--refresh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def main():
    if not PALETTE.is_file():
        sys.exit(f"render/dunst: missing {PALETTE}")
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ensure_base()

    p = json.loads(PALETTE.read_text())
    bg = p["bg"]
    fg = p["fg"]
    c = p["colors"]
    pack = (
        p.get("source", "").removeprefix("theme:")
        if p.get("source", "").startswith("theme:")
        else ""
    )
    overrides = load_pack_overrides(pack)
    variant = p.get("background", "dark")
    if variant not in ("dark", "light"):
        variant = "dark"
    template = {} if pack else load_dunst_template(variant, bg, fg, c)

    def role(name, fallback):
        return overrides.get(name) or template.get(name) or fallback

    bg_primary = role("bg-primary", first(bg, c[0], "#1e1e2e"))
    bg_secondary = role("bg-secondary", bg_primary)
    bg_tertiary = role("bg-tertiary", bg_primary)
    fg_primary = role("fg-primary", first(fg, c[15], "#f8f8f2"))
    fg_secondary = role("fg-secondary", fg_primary)
    border_primary = role("border-primary", first(c[4], c[12], "#6272a4"))
    border_secondary = role("border-secondary", first(c[8], border_primary, "#44475a"))
    accent_red = role("accent-red", first(c[1], c[9], "#ff5555"))
    accent_green = role("accent-green", first(c[2], c[10], border_primary, "#50fa7b"))
    accent_yellow = role("accent-yellow", first(c[3], c[11], border_primary, "#f1fa8c"))
    accent_blue = role("accent-blue", first(c[4], c[12], border_primary, "#8be9fd"))
    accent_purple = role("accent-purple", first(c[5], c[13], accent_blue, "#bd93f9"))
    accent_aqua = role("accent-aqua", first(c[6], c[14], accent_blue, "#8be9fd"))
    accent_orange = role("accent-orange", first(c[11], c[3], accent_red, "#ffb86c"))
    gray = role("gray", first(c[8], border_secondary, "#6272a4"))

    bg_critical = role("bg-critical", bg_primary)
    fg_critical = role("fg-critical", fg_primary)
    frame_critical = role("frame-critical", accent_red)

    bg_low_render = with_alpha(bg_secondary, "80")
    bg_normal_render = with_alpha(bg_primary, "80")
    bg_category_render = with_alpha(bg_tertiary, "80")
    bg_critical_render = with_alpha(bg_critical, "80")
    fg_low_render = with_alpha(fg_secondary, "E6")
    fg_normal_render = with_alpha(fg_primary, "E6")
    fg_category_render = with_alpha(fg_primary, "E6")
    fg_critical_render = with_alpha(fg_critical, "E6")
    frame_low_render = with_alpha(border_secondary, "33")
    frame_normal_render = with_alpha(border_primary, "55")
    frame_critical_render = with_alpha(frame_critical, "CC")
    progress_fg = accent_blue
    cat_email = with_alpha(accent_blue, "55")
    cat_chat = with_alpha(accent_aqua, "55")
    cat_warning = with_alpha(accent_yellow, "55")
    cat_error = with_alpha(accent_red, "55")
    cat_network = with_alpha(accent_blue, "55")
    cat_battery = with_alpha(accent_orange, "55")
    cat_update = with_alpha(accent_green, "55")
    cat_music = with_alpha(accent_purple, "55")
    cat_volume = with_alpha(gray, "55")

    # Layout metrics
    rounding = resolve_metric("rounding", "decoration:rounding", "5")
    gaps_in = resolve_metric("gaps_in", "general:gaps_in", "5")
    gaps_out = resolve_metric("gaps_out", "general:gaps_out", "6")
    border_size = resolve_metric("border_size", "general:border_size", "2")
    try:
        gap_size = int(gaps_in) * 2
    except ValueError:
        gap_size = 10
    try:
        edge_padding = int(gaps_out) * 2 + int(border_size)
    except ValueError:
        edge_padding = 14

    pos = waybar_position()
    origin = {"left": "top-left", "bottom": "bottom-right", "top": "top-right"}.get(
        pos, "top-right"
    )

    # Font
    icon_theme = first(
        os.environ.get("ICON_THEME"),
        os.environ.get("GTK_ICON"),
        read_theme_var("ICON_THEME"),
    )
    if not icon_theme:
        try:
            out = (
                subprocess.run(
                    ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
                    capture_output=True,
                    text=True,
                )
                .stdout.strip()
                .strip("'")
            )
            icon_theme = out
        except FileNotFoundError:
            pass
    icon_theme = icon_theme or "hicolor"

    notification_font = first(
        os.environ.get("NOTIFICATION_FONT"),
        read_layer_var("NOTIFICATION_FONT"),
        read_layer_var("FONT"),
    )
    font_size_env = os.environ.get("FONT_SIZE", "")
    notification_font_size = (
        font_size_env
        if font_size_env.isdigit()
        else (read_theme_var("FONT_SIZE") or "10")
    )
    if not notification_font_size.isdigit():
        notification_font_size = "10"
    font_line = (
        f"    font = {notification_font} {notification_font_size}"
        if notification_font
        else ""
    )

    # Cache key
    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    if BASE_CONF.is_file():
        hasher.update(BASE_CONF.read_bytes())
    if pack:
        dt = THEMES_DIR / pack / "dunst.theme"
        if dt.is_file():
            hasher.update(dt.read_bytes())
    for s in (
        rounding,
        gaps_in,
        border_size,
        origin,
        str(edge_padding),
        notification_font,
        notification_font_size,
        icon_theme,
        bg_normal_render,
        fg_normal_render,
        frame_normal_render,
        progress_fg,
    ):
        hasher.update(str(s).encode())
    hasher.update(Path(__file__).read_bytes())
    hasher.update(variant.encode())
    for f in dunst_template_layers(variant):
        hasher.update(f.read_bytes())
    h = hasher.hexdigest()[:16]

    if (
        cache_hit(APP, h)
        and DUNST_CONF.exists()
        and OUT_FILE.exists()
        and ROLES_FILE.exists()
    ):
        return

    base = (
        BASE_CONF.read_text() if BASE_CONF.is_file() else "[global]\n    monitor = 0\n"
    )

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

    try:
        corner_radius = int(rounding) * 3 // 2
    except ValueError:
        corner_radius = 7

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
    frame_color = "{frame_critical_render}"
    highlight = "{frame_critical_render}"
    timeout = 0
{category_rule("email", "email", cat_email)}
{category_rule("chat", "chat", cat_chat)}
{category_rule("warning", "warning", cat_warning)}
{category_rule("error", "error", cat_error)}
{category_rule("network", "network", cat_network)}
{category_rule("battery", "battery", cat_battery)}
{category_rule("update", "update", cat_update)}
{category_rule("music", "music", cat_music)}
{category_rule("volume", "volume", cat_volume)}

[submap_hint]
    stack_tag = "submap-hint"
    history_ignore = yes
    format = "<span foreground='{accent_red}'>%s</span>\\n%b"
    foreground = "{fg_low_render}"
"""

    roles = {
        "fg-primary": fg_primary,
        "fg-secondary": fg_secondary,
        "bg-primary": bg_primary,
        "bg-secondary": bg_secondary,
        "bg-tertiary": bg_tertiary,
        "accent-red": accent_red,
        "accent-green": accent_green,
        "accent-yellow": accent_yellow,
        "accent-blue": accent_blue,
        "accent-purple": accent_purple,
        "accent-aqua": accent_aqua,
        "accent-orange": accent_orange,
        "border-primary": border_primary,
        "border-secondary": border_secondary,
        "gray": gray,
    }
    roles_content = "".join(
        f"@define-color {name} {value};\n" for name, value in roles.items()
    )

    # Write to both render cache + live dunstrc (dunst reads dunstrc directly)
    for target in (OUT_FILE, DUNST_CONF):
        atomic_write(target, content)
    atomic_write(ROLES_FILE, roles_content)

    cache_store(APP, h)
    reload_dunst()


if __name__ == "__main__":
    main()
