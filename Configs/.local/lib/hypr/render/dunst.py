#!/usr/bin/env python3
# Renderer: dunst dunstrc (palette overlay + Hyprland-derived layout + category rules).
# Writes ~/.config/dunst/dunstrc and reloads dunst.

import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
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


@dataclass(frozen=True)
class DunstColors:
    roles: dict
    urgency: dict
    categories: dict
    progress_fg: str


@dataclass(frozen=True)
class DunstLayout:
    rounding: str
    gaps_in: str
    border_size: str
    gap_size: int
    edge_padding: int
    origin: str


@dataclass(frozen=True)
class DunstFont:
    icon_theme: str
    name: str
    size: str

    @property
    def config_line(self):
        return f"    font = {self.name} {self.size}" if self.name else ""


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
    except (
        OSError,
        subprocess.CalledProcessError,
        json.JSONDecodeError,
        TypeError,
        ValueError,
    ):
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
        except OSError:
            return "right"
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
                check=False,
            ).returncode
            != 0
        ):
            return
    except FileNotFoundError:
        return
    if (
        subprocess.run(
            ["dunstctl", "reload"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        != 0
    ):
        subprocess.run(
            ["pkill", "-HUP", "-x", "dunst"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    refresh_submap_hint()


def refresh_submap_hint():
    # The reload restyles only new notifications; a submap hint on screen
    # would keep the previous palette until the submap is re-entered.
    hint_script = Path(__file__).resolve().parent.parent / "keybinds" / "submap-hint.sh"
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


def resolve_colors(palette):
    bg = palette["bg"]
    fg = palette["fg"]
    colors = palette["colors"]
    pack = (
        palette.get("source", "").removeprefix("theme:")
        if palette.get("source", "").startswith("theme:")
        else ""
    )
    overrides = load_pack_overrides(pack)
    variant = palette.get("background", "dark")
    if variant not in ("dark", "light"):
        variant = "dark"
    template = {} if pack else load_dunst_template(variant, bg, fg, colors)

    def role(name, fallback):
        return overrides.get(name) or template.get(name) or fallback

    bg_primary = role("bg-primary", first(bg, colors[0], "#1e1e2e"))
    bg_secondary = role("bg-secondary", bg_primary)
    bg_tertiary = role("bg-tertiary", bg_primary)
    fg_primary = role("fg-primary", first(fg, colors[15], "#f8f8f2"))
    fg_secondary = role("fg-secondary", fg_primary)
    border_primary = role("border-primary", first(colors[4], colors[12], "#6272a4"))
    border_secondary = role(
        "border-secondary", first(colors[8], border_primary, "#44475a")
    )
    accent_red = role("accent-red", first(colors[1], colors[9], "#ff5555"))
    accent_green = role(
        "accent-green",
        first(colors[2], colors[10], border_primary, "#50fa7b"),
    )
    accent_yellow = role(
        "accent-yellow",
        first(colors[3], colors[11], border_primary, "#f1fa8c"),
    )
    accent_blue = role(
        "accent-blue",
        first(colors[4], colors[12], border_primary, "#8be9fd"),
    )
    accent_purple = role(
        "accent-purple",
        first(colors[5], colors[13], accent_blue, "#bd93f9"),
    )
    accent_aqua = role(
        "accent-aqua",
        first(colors[6], colors[14], accent_blue, "#8be9fd"),
    )
    accent_orange = role(
        "accent-orange",
        first(colors[11], colors[3], accent_red, "#ffb86c"),
    )
    gray = role("gray", first(colors[8], border_secondary, "#6272a4"))

    bg_critical = role("bg-critical", bg_primary)
    fg_critical = role("fg-critical", fg_primary)
    frame_critical = role("frame-critical", accent_red)

    resolved = DunstColors(
        roles={
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
        },
        urgency={
            "low": {
                "background": with_alpha(bg_secondary, "80"),
                "foreground": with_alpha(fg_secondary, "E6"),
                "frame": with_alpha(border_secondary, "33"),
            },
            "normal": {
                "background": with_alpha(bg_primary, "80"),
                "foreground": with_alpha(fg_primary, "E6"),
                "frame": with_alpha(border_primary, "55"),
            },
            "critical": {
                "background": with_alpha(bg_critical, "80"),
                "foreground": with_alpha(fg_critical, "E6"),
                "frame": with_alpha(frame_critical, "CC"),
            },
            "category": {
                "background": with_alpha(bg_tertiary, "80"),
                "foreground": with_alpha(fg_primary, "E6"),
            },
        },
        categories={
            "email": with_alpha(accent_blue, "55"),
            "chat": with_alpha(accent_aqua, "55"),
            "warning": with_alpha(accent_yellow, "55"),
            "error": with_alpha(accent_red, "55"),
            "network": with_alpha(accent_blue, "55"),
            "battery": with_alpha(accent_orange, "55"),
            "update": with_alpha(accent_green, "55"),
            "music": with_alpha(accent_purple, "55"),
            "volume": with_alpha(gray, "55"),
        },
        progress_fg=accent_blue,
    )
    return pack, variant, resolved


def resolve_layout():
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

    origin = {
        "left": "top-left",
        "bottom": "bottom-right",
        "top": "top-right",
    }.get(waybar_position(), "top-right")
    return DunstLayout(
        rounding=rounding,
        gaps_in=gaps_in,
        border_size=border_size,
        gap_size=gap_size,
        edge_padding=edge_padding,
        origin=origin,
    )


def resolve_icon_theme():
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
                    check=False,
                )
                .stdout.strip()
                .strip("'")
            )
            icon_theme = out
        except FileNotFoundError:
            pass
    return icon_theme or "hicolor"


def resolve_font():
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
    return DunstFont(
        icon_theme=resolve_icon_theme(),
        name=notification_font,
        size=notification_font_size,
    )


def renderer_hash(pack, variant, colors, layout, font):
    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    if BASE_CONF.is_file():
        hasher.update(BASE_CONF.read_bytes())
    if pack:
        dt = THEMES_DIR / pack / "dunst.theme"
        if dt.is_file():
            hasher.update(dt.read_bytes())
    for s in (
        layout.rounding,
        layout.gaps_in,
        layout.border_size,
        layout.origin,
        str(layout.edge_padding),
        font.name,
        font.size,
        font.icon_theme,
        colors.urgency["normal"]["background"],
        colors.urgency["normal"]["foreground"],
        colors.urgency["normal"]["frame"],
        colors.progress_fg,
    ):
        hasher.update(str(s).encode())
    hasher.update(Path(__file__).read_bytes())
    hasher.update(variant.encode())
    for f in dunst_template_layers(variant):
        hasher.update(f.read_bytes())
    return hasher.hexdigest()[:16]


def category_rule(section, category, color, colors):
    out = []
    for urgency in ("low", "normal"):
        out.append(f"""
[category_{section}_{urgency}]
    category = {category}
    msg_urgency = {urgency}
    background = "{colors.urgency["category"]["background"]}"
    foreground = "{colors.urgency["category"]["foreground"]}"
    frame_color = "{color}"
    highlight = "{color}"
    timeout = 2""")
    return "".join(out)


def category_rules(colors):
    return "\n".join(
        category_rule(name, name, color, colors)
        for name, color in colors.categories.items()
    )


def render_config(base, colors, layout, font):
    try:
        corner_radius = int(layout.rounding) * 3 // 2
    except ValueError:
        corner_radius = 7

    return f"""# WARNING: This file is auto-generated by render/dunst.
# DO NOT edit manually.
# Edit '{BASE_CONF}' to change the base configuration.

{base}

# Dynamic overrides generated from active palette + Hyprland state.
[global]
    monitor = 0
    origin = {layout.origin}
    offset = ({layout.edge_padding},{layout.edge_padding})
    gap_size = {layout.gap_size}
    frame_width = {layout.border_size}
    progress_bar_corner_radius = {layout.rounding}
    icon_theme = "{font.icon_theme}"
    corner_radius = {corner_radius}
    icon_corner_radius = {layout.rounding}
{font.config_line}

[urgency_low]
    background = "{colors.urgency["low"]["background"]}"
    foreground = "{colors.urgency["low"]["foreground"]}"
    frame_color = "{colors.urgency["low"]["frame"]}"
    highlight = "{colors.progress_fg}"
    timeout = 2

[urgency_normal]
    background = "{colors.urgency["normal"]["background"]}"
    foreground = "{colors.urgency["normal"]["foreground"]}"
    frame_color = "{colors.urgency["normal"]["frame"]}"
    highlight = "{colors.progress_fg}"
    timeout = 2

[urgency_critical]
    background = "{colors.urgency["critical"]["background"]}"
    foreground = "{colors.urgency["critical"]["foreground"]}"
    frame_color = "{colors.urgency["critical"]["frame"]}"
    highlight = "{colors.urgency["critical"]["frame"]}"
    timeout = 0
{category_rules(colors)}

[submap_hint]
    stack_tag = "submap-hint"
    history_ignore = yes
    format = "<span foreground='{colors.roles["accent-red"]}'>%s</span>\\n%b"
    foreground = "{colors.urgency["low"]["foreground"]}"
"""


def render_roles(colors):
    return "".join(
        f"@define-color {name} {value};\n" for name, value in colors.roles.items()
    )


def main():
    if not PALETTE.is_file():
        sys.exit(f"render/dunst: missing {PALETTE}")
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ensure_base()

    palette = json.loads(PALETTE.read_text())
    pack, variant, colors = resolve_colors(palette)
    layout = resolve_layout()
    font = resolve_font()
    cache_key = renderer_hash(pack, variant, colors, layout, font)
    if (
        cache_hit(APP, cache_key)
        and DUNST_CONF.exists()
        and OUT_FILE.exists()
        and ROLES_FILE.exists()
    ):
        return

    base = (
        BASE_CONF.read_text() if BASE_CONF.is_file() else "[global]\n    monitor = 0\n"
    )
    content = render_config(base, colors, layout, font)
    # Write to both render cache + live dunstrc (dunst reads dunstrc directly)
    for target in (OUT_FILE, DUNST_CONF):
        atomic_write(target, content)
    atomic_write(ROLES_FILE, render_roles(colors))

    cache_store(APP, cache_key)
    reload_dunst()


if __name__ == "__main__":
    main()
