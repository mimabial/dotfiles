import json
import os
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from kitty.boss import get_boss
from kitty.fast_data_types import Screen, add_timer, get_os_window_title
from kitty.rgb import Color
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    Formatter,
    TabBarData,
    as_rgb,
    draw_attributed_string,
    draw_title,
)
from kitty.utils import color_as_int

timer_id = None

ICON = " 󰾰 "
RIGHT_MARGIN = 1
REFRESH_TIME = 15

# Wallbash theme config path
THEME_CONFIG_PATH = Path.home() / ".config" / "kitty" / "theme.conf"

# Fallback colors (original hardcoded values)
FALLBACK_COLORS = {
    "icon_fg": "#FFFACD",
    "icon_bg": "#2F3D44", 
    "bat_text": "#999F93",
    "clock": "#7FBBB3",
    "separator": "#999F93",
    "utc": "#717374"
}

def load_wallbash_colors():
    """Load colors from kitty theme.conf file with fallback to defaults."""
    colors = FALLBACK_COLORS.copy()
    
    if THEME_CONFIG_PATH.exists():
        try:
            theme_colors = {}
            with open(THEME_CONFIG_PATH, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        parts = line.split()
                        if len(parts) >= 2:
                            theme_colors[parts[0]] = parts[1]
            
            # Map theme colors to our usage
            color_mapping = {
                "icon_fg": theme_colors.get("foreground", theme_colors.get("color15", colors["icon_fg"])),
                "icon_bg": theme_colors.get("background", theme_colors.get("color0", colors["icon_bg"])),
                "bat_text": theme_colors.get("color8", colors["bat_text"]), 
                "clock": theme_colors.get("color6", colors["clock"]),
                "separator": theme_colors.get("color8", colors["separator"]),
                "utc": theme_colors.get("color8", colors["utc"])
            }
            
            colors.update(color_mapping)
                
        except (OSError, ValueError):
            pass
    
    return colors

def hex_to_rgb_int(hex_color):
    """Convert hex color to RGB integer."""
    if hex_color.startswith('#'):
        hex_color = hex_color[1:]
    return int(hex_color, 16)

# Load colors dynamically
_colors = load_wallbash_colors()
icon_fg = as_rgb(hex_to_rgb_int(_colors["icon_fg"]))
icon_bg = as_rgb(hex_to_rgb_int(_colors["icon_bg"]))
bat_text_color = as_rgb(hex_to_rgb_int(_colors["bat_text"]))
clock_color = as_rgb(hex_to_rgb_int(_colors["clock"]))
sep_color = as_rgb(hex_to_rgb_int(_colors["separator"]))
utc_color = as_rgb(hex_to_rgb_int(_colors["utc"]))

def refresh_colors():
    """Refresh colors from wallbash config - called periodically."""
    global icon_fg, icon_bg, bat_text_color, clock_color, sep_color, utc_color
    
    colors = load_wallbash_colors()
    icon_fg = as_rgb(hex_to_rgb_int(colors["icon_fg"]))
    icon_bg = as_rgb(hex_to_rgb_int(colors["icon_bg"]))
    bat_text_color = as_rgb(hex_to_rgb_int(colors["bat_text"]))
    clock_color = as_rgb(hex_to_rgb_int(colors["clock"]))
    sep_color = as_rgb(hex_to_rgb_int(colors["separator"]))
    utc_color = as_rgb(hex_to_rgb_int(colors["utc"]))

def calc_draw_spaces(*args) -> int:
    length = 0
    for i in args:
        if not isinstance(i, str):
            i = str(i)
        length += len(i)
    return length


def _draw_icon(screen: Screen, index: int) -> int:
    if index != 1:
        return 0

    fg, bg = screen.cursor.fg, screen.cursor.bg
    screen.cursor.fg = icon_fg
    screen.cursor.bg = icon_bg
    screen.draw(ICON)
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.x = len(ICON)
    return screen.cursor.x

def _draw_left_status(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    if draw_data.leading_spaces:
        screen.draw(" " * draw_data.leading_spaces)

    draw_title(draw_data, screen, tab, index)
    trailing_spaces = min(max_title_length - 1, draw_data.trailing_spaces)
    max_title_length -= trailing_spaces
    extra = screen.cursor.x - before - max_title_length
    if extra > 0:
        screen.cursor.x -= extra + 1
        screen.draw("…")
    if trailing_spaces:
        screen.draw(" " * trailing_spaces)
    end = screen.cursor.x
    screen.cursor.bold = screen.cursor.italic = False
    screen.cursor.fg = 0
    if not is_last:
        screen.cursor.bg = as_rgb(color_as_int(draw_data.inactive_bg))
        screen.draw(draw_data.sep)
    screen.cursor.bg = 0
    return end

def _draw_right_status(screen: Screen, is_last: bool) -> int:
    if not is_last:
        return 0

    draw_attributed_string(Formatter.reset, screen)

    clock = datetime.now().strftime("%H:%M")
    utc = datetime.now(timezone.utc).strftime(" (UTC %H:%M)")

    cells = []

    cells.append((clock_color, clock))
    cells.append((utc_color, utc))

    right_status_length = RIGHT_MARGIN
    for cell in cells:
        right_status_length += len(str(cell[1]))

    draw_spaces = screen.columns - screen.cursor.x - right_status_length

    if draw_spaces > 0:
        screen.draw(" " * draw_spaces)

    screen.cursor.fg = 0
    for color, status in cells:
        screen.cursor.fg = color  # as_rgb(color_as_int(color))
        screen.draw(status)
    screen.cursor.bg = 0

    if screen.columns - screen.cursor.x > right_status_length:
        screen.cursor.x = screen.columns - right_status_length

    return screen.cursor.x

def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    if timer_id is None:
        add_timer(refresh_colors, REFRESH_TIME, True)

    _draw_icon(screen, index)
    _draw_left_status(
        draw_data,
        screen,
        tab,
        before,
        max_title_length,
        index,
        is_last,
        extra_data,
    )
    _draw_right_status(
        screen,
        is_last,
    )

    return screen.cursor.x
