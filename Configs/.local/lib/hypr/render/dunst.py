#!/usr/bin/env python3
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import atomic_write, cache_hit, cache_store, short_digest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pyutils.bar_position import bar_position
from pyutils.hyprctl import batch_json
from pyutils.lock_paths import runtime_lock_path
from pyutils.shell_env import load_shell_assignments

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
OUT_DIR = (
    Path(os.environ.get("HYPR_CACHE_HOME", os.path.expanduser("~/.cache/hypr")))
    / "render"
    / "dunst"
)
OUT_FILE = OUT_DIR / "dunstrc"
ROLES_FILE = OUT_DIR / "colors.conf"
BACKGROUND_ALPHA = "80"
TEXT_ALPHA = "E6"
CATEGORY_ALPHA = "55"
FRAME_ALPHA = {"low": "33", "normal": "55", "critical": "CC"}
WINDOWS_WORKFLOW_ALPHA = "E6"
OPAQUE_ALPHA = "FF"
FALLBACK_CORNER_RADIUS = 7
URGENCY_TIMEOUT_SECONDS = {"low": 2, "normal": 2, "critical": 0}
CATEGORY_ROLES = {
    "email": "accent-blue",
    "chat": "accent-aqua",
    "warning": "accent-yellow",
    "error": "accent-red",
    "network": "accent-blue",
    "battery": "accent-orange",
    "update": "accent-green",
    "music": "accent-purple",
    "volume": "gray",
}
FALLBACK_COLORS = {
    "bg-primary": "#1e1e2e",
    "fg-primary": "#f8f8f2",
    "border-primary": "#6272a4",
    "border-secondary": "#44475a",
    "accent-red": "#ff5555",
    "accent-green": "#50fa7b",
    "accent-yellow": "#f1fa8c",
    "accent-blue": "#8be9fd",
    "accent-purple": "#bd93f9",
    "accent-aqua": "#8be9fd",
    "accent-orange": "#ffb86c",
    "gray": "#6272a4",
}
WAL_TEMPLATES_DIR = (
    Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
    / "wal"
    / "templates"
)

APP = "dunst"
# the 1.0 anchor for the text-size knob, matching system/text-size.sh
BASE_PX = 12
# A face carrying no Nerd Font glyphs makes fontconfig pick the fallback per
# glyph, so a notification body lands in some unrelated proportional font.
# Miracode is Monocraft's vector reinterpretation and inherits its cell width,
# but none of its icons. quickshell/shell.qml borrows only icons, so its map
# can name a different face.
GLYPH_COMPANIONS = {"Miracode": "Monocraft"}
STATE_FILE = Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr")) / "staterc"


DEFAULT_WIDTH = 300
DEFAULT_HEIGHT = (0, 600)
FALLBACK_EDGE_PADDING = 14


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
    width: int
    height: str


@dataclass(frozen=True)
class DunstFont:
    icon_theme: str
    name: str
    size: str

    @property
    def config_line(self):
        return f"    font = {self.name} {self.size}" if self.name else ""


def first_nonempty(*values):
    for value in values:
        if value:
            return value
    return ""


def with_alpha(color, alpha_hex):
    rgb = color.lstrip("#")
    alpha = alpha_hex.lstrip("#").upper()
    if len(rgb) == 8:
        return "#" + rgb[:6].upper() + alpha
    if len(rgb) == 6:
        return "#" + rgb.upper() + alpha
    return "#" + rgb


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


# Mirrors hypr_config_layer_files() / hypr_config_parse_layer_file() in core/config-layers.bash.
_VARS_SET_RX = re.compile(r'^\s*vars\.set\("([^"]+)",\s*"([^"]*)"\)')
_VARS_TABLE_FIELD_RX = re.compile(r'^\s*(?:\["([^"]+)"\]|([A-Za-z_]\w*))\s*=\s*"([^"]*)",?\s*$')
_layer_cache = None


def _layer_files():
    config_home = Path(
        os.environ.get("HYPR_CONFIG_HOME", os.path.expanduser("~/.config/hypr"))
    )
    data_home = Path(
        os.environ.get("HYPR_DATA_HOME", os.path.expanduser("~/.local/share/hypr"))
    )
    vars_file = config_home / "vars.lua"
    if not vars_file.is_file():
        vars_file = data_home / "vars.lua"
    return (config_home / "userprefs.lua", config_home / "userfonts.lua", THEME_CONF, vars_file)


def _layer_cache_get():
    global _layer_cache
    if _layer_cache is not None:
        return _layer_cache
    vars_d = {}
    for path in _layer_files():
        if not path.is_file():
            continue
        is_vars_table = path.name == "vars.lua"
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            m = _VARS_SET_RX.match(line)
            field = is_vars_table and _VARS_TABLE_FIELD_RX.match(line)
            if m:
                key, value = m.group(1), m.group(2)
            elif field:
                key, value = field.group(1) or field.group(2), field.group(3)
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


def read_hypr_metrics(options):
    if not options:
        return {}
    try:
        values = batch_json(*(f"getoption {option}" for option in options))
        return {option: str(value.get("int", "")) for option, value in zip(options, values)}
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, TypeError, ValueError):
        return {}


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
    if not pack_name:
        return {}
    theme_path = THEMES_DIR / pack_name / "dunst.theme"
    if not theme_path.is_file():
        return {}
    return _parse_define_colors(theme_path.read_text())


def dunst_template_layers(variant):
    layers = []
    for name in ("colors-dunst.theme", f"colors-dunst.{variant}.theme"):
        template_path = WAL_TEMPLATES_DIR / name
        if template_path.is_file():
            layers.append(template_path)
    return layers


def load_dunst_template(variant, bg, fg, colors):
    """colors-dunst.<variant>.theme wins over the shared colors-dunst.theme; both files
    are sparse and list only the roles they override."""
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


def ensure_base_dunst_config():
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
    workflow = load_shell_assignments(STATE_FILE).get("HYPR_WORKFLOW")
    for rule in ("windows_90", "gaming_opaque", "powersaver_opaque"):
        state = "enable" if workflow == rule.split("_", 1)[0] else "disable"
        subprocess.run(["dunstctl", "rule", rule, state], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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


def palette_roles(role, bg, fg, colors):
    bg_primary = role("bg-primary", bg, colors[0])
    fg_primary = role("fg-primary", fg, colors[15])
    border_primary = role("border-primary", colors[4], colors[12])
    border_secondary = role("border-secondary", colors[8], border_primary)
    accent_red = role("accent-red", colors[1], colors[9])
    accent_blue = role("accent-blue", colors[4], colors[12], border_primary)
    return {
        "fg-primary": fg_primary,
        "fg-secondary": role("fg-secondary", fg_primary),
        "bg-primary": bg_primary,
        "bg-secondary": role("bg-secondary", bg_primary),
        "bg-tertiary": role("bg-tertiary", bg_primary),
        "accent-red": accent_red,
        "accent-green": role("accent-green", colors[2], colors[10], border_primary),
        "accent-yellow": role("accent-yellow", colors[3], colors[11], border_primary),
        "accent-blue": accent_blue,
        "accent-purple": role("accent-purple", colors[5], colors[13], accent_blue),
        "accent-aqua": role("accent-aqua", colors[6], colors[14], accent_blue),
        "accent-orange": role("accent-orange", colors[11], colors[3], accent_red),
        "border-primary": border_primary,
        "border-secondary": border_secondary,
        "gray": role("gray", colors[8], border_secondary),
    }


def urgency_style(level, background, foreground, frame=None):
    styled = {
        "background": with_alpha(background, BACKGROUND_ALPHA),
        "foreground": with_alpha(foreground, TEXT_ALPHA),
    }
    if frame:
        styled["frame"] = with_alpha(frame, FRAME_ALPHA[level])
    return styled


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

    def role(name, *candidates):
        return (
            overrides.get(name)
            or template.get(name)
            or first_nonempty(*candidates, FALLBACK_COLORS.get(name))
        )

    roles = palette_roles(role, bg, fg, colors)
    bg_critical = role("bg-critical", roles["bg-primary"])
    fg_critical = role("fg-critical", roles["fg-primary"])
    frame_critical = role("frame-critical", roles["accent-red"])

    resolved = DunstColors(
        roles=roles,
        urgency={
            "low": urgency_style("low", roles["bg-secondary"], roles["fg-secondary"], roles["border-secondary"]),
            "normal": urgency_style("normal", roles["bg-primary"], roles["fg-primary"], roles["border-primary"]),
            "critical": urgency_style("critical", bg_critical, fg_critical, frame_critical),
            "category": urgency_style("category", roles["bg-tertiary"], roles["fg-primary"]),
        },
        categories={
            category: with_alpha(roles[role_name], CATEGORY_ALPHA)
            for category, role_name in CATEGORY_ROLES.items()
        },
        progress_fg=roles["accent-blue"],
    )
    return pack, variant, resolved


def text_size_px():
    """system/text-size.sh owns it."""
    try:
        return int(load_shell_assignments(STATE_FILE).get("TEXT_SIZE", str(BASE_PX)))
    except (OSError, ValueError):
        return BASE_PX


def text_scale():
    """For pixel geometry; 12px is the 1.0 anchor."""
    return text_size_px() / BASE_PX


def base_metric(name, default):
    if BASE_CONF.is_file():
        for line in BASE_CONF.read_text().splitlines():
            match = re.match(rf"^\s*{name}\s*=\s*(\d+)", line)
            if match:
                return int(match.group(1))
    return default


def base_height():
    """dunst also accepts a bare number there, which it reads as the maximum."""
    raw = ""
    if BASE_CONF.is_file():
        for line in BASE_CONF.read_text().splitlines():
            match = re.match(r"^\s*height\s*=\s*(\(?\s*\d+(?:\s*,\s*\d+)?\s*\)?)", line)
            if match:
                raw = match.group(1)
                break
    numbers = [int(value) for value in re.findall(r"\d+", raw)] or list(DEFAULT_HEIGHT)
    scaled = [max(0, round(value * text_scale())) for value in numbers]
    return f"({scaled[0]},{scaled[1]})" if len(scaled) > 1 else str(scaled[0])


def resolve_layout():
    specs = (
        ("rounding", "decoration:rounding", "5"),
        ("gaps_in", "general:gaps_in", "5"),
        ("gaps_out", "general:gaps_out", "6"),
        ("border_size", "general:border_size", "2"),
    )
    metrics = {key: read_theme_metric(key) for key, _, _ in specs}
    live = read_hypr_metrics([option for key, option, _ in specs if not metrics[key]])
    rounding, gaps_in, gaps_out, border_size = (
        metrics[key] or live.get(option) or default for key, option, default in specs
    )

    try:
        gap_size = int(gaps_in) * 2
    except ValueError:
        gap_size = 10
    try:
        edge_padding = int(gaps_out) * 2 + int(border_size)
    except ValueError:
        edge_padding = FALLBACK_EDGE_PADDING

    width = max(1, round(base_metric("width", DEFAULT_WIDTH) * text_scale()))
    origin = {
        "bottom": "bottom-right",
        "top": "top-right",
    }.get(bar_position(), "top-right")
    return DunstLayout(
        rounding=rounding,
        gaps_in=gaps_in,
        border_size=border_size,
        gap_size=gap_size,
        edge_padding=edge_padding,
        origin=origin,
        width=width,
        height=base_height(),
    )


def resolve_icon_theme():
    icon_theme = first_nonempty(
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
    notification_font = first_nonempty(
        os.environ.get("NOTIFICATION_FONT"),
        read_layer_var("NOTIFICATION_FONT"),
        read_layer_var("FONT"),
    )
    notification_font = GLYPH_COMPANIONS.get(notification_font, notification_font)
    font_size_env = os.environ.get("FONT_SIZE", "")
    notification_font_size = (
        font_size_env
        if font_size_env.isdigit()
        else (read_theme_var("FONT_SIZE") or "10")
    )
    if not notification_font_size.isdigit():
        notification_font_size = "10"
    # Integer division, not rounding: system/text-size.sh derives rofi's point size
    # the same way, and the launcher and the notification stack share the same 10pt
    # base - rounding here landed them a point apart at most text sizes.
    notification_font_size = str(
        max(1, int(notification_font_size) * text_size_px() // BASE_PX)
    )
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
        str(layout.width),
        layout.height,
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
    return short_digest(hasher)


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


def corner_radius(rounding):
    try:
        return int(rounding) * 3 // 2
    except ValueError:
        return FALLBACK_CORNER_RADIUS


def urgency_section(level, style, highlight):
    return f"""[urgency_{level}]
    background = "{style["background"]}"
    foreground = "{style["foreground"]}"
    frame_color = "{style["frame"]}"
    highlight = "{highlight}"
    timeout = {URGENCY_TIMEOUT_SECONDS[level]}
"""


def workflow_background_rule(name, colors, alpha):
    return f"""[{name}]
    enabled = no
    background = "{with_alpha(colors.roles["bg-primary"], alpha)}"
"""


def render_config(base, colors, layout, font):
    critical_frame = colors.urgency["critical"]["frame"]
    return f"""# WARNING: This file is auto-generated by render/dunst.
# DO NOT edit manually.
# Edit '{BASE_CONF}' to change the base configuration.

{base}

# Dynamic overrides generated from active palette + Hyprland state.
[global]
    monitor = 0
    origin = {layout.origin}
    width = {layout.width}
    height = {layout.height}
    offset = ({layout.edge_padding},{layout.edge_padding})
    gap_size = {layout.gap_size}
    frame_width = {layout.border_size}
    progress_bar_corner_radius = {layout.rounding}
    icon_theme = "{font.icon_theme}"
    corner_radius = {corner_radius(layout.rounding)}
    icon_corner_radius = {layout.rounding}
{font.config_line}

{urgency_section("low", colors.urgency["low"], colors.progress_fg)}
{urgency_section("normal", colors.urgency["normal"], colors.progress_fg)}
{urgency_section("critical", colors.urgency["critical"], critical_frame)}{category_rules(colors)}

[submap_hint]
    stack_tag = "submap-hint"
    history_ignore = yes
    format = "<span foreground='{colors.roles["accent-red"]}'>%s</span>\\n%b"
    foreground = "{colors.urgency["low"]["foreground"]}"

{workflow_background_rule("windows_90", colors, WINDOWS_WORKFLOW_ALPHA)}
{workflow_background_rule("gaming_opaque", colors, OPAQUE_ALPHA)}
{workflow_background_rule("powersaver_opaque", colors, OPAQUE_ALPHA)}"""


def render_roles(colors):
    return "".join(
        f"@define-color {name} {value};\n" for name, value in colors.roles.items()
    )


def render():
    if not PALETTE.is_file():
        sys.exit(f"render/dunst: missing {PALETTE}")
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ensure_base_dunst_config()

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
    for target in (OUT_FILE, DUNST_CONF):
        atomic_write(target, content)
    atomic_write(ROLES_FILE, render_roles(colors))

    cache_store(APP, cache_key)
    reload_dunst()


def main():
    lock_file = runtime_lock_path("dunst_render")
    with lock_file.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        render()


if __name__ == "__main__":
    main()
