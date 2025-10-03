from datetime import datetime, timezone
from pathlib import Path

from kitty.fast_data_types import Screen
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

ICON = " 󱚠 TERM "
RIGHT_MARGIN = 1

# Wallbash theme config path
THEME_CONFIG_PATH = Path.home() / ".config" / "kitty" / "theme.conf"

# Track file modification time
_last_mtime = None

# Fallback colors (original hardcoded values)
FALLBACK_COLORS = {
    "icon_fg": "#FFFACD",
    "icon_bg": "#2F3D44", 
    "bat_text": "#999F93",
    "clock": "#7FBBB3",
    "separator": "#999F93",
    "utc": "#717374",
    "inactive_tab_fg": "#555555",  # color8 
    "active_tab_fg": "#00FFE6",    # color6
    "inactive_tab_bg": "#000000",  # inactive_tab_background
    "active_tab_bg": "#56A0D3"     # active_tab_background
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
                "utc": theme_colors.get("color8", colors["utc"]),
                "inactive_tab_fg": theme_colors.get("color8", colors["inactive_tab_fg"]),
                "active_tab_fg": theme_colors.get("color4", colors["active_tab_fg"]),
                "inactive_tab_bg": theme_colors.get("inactive_tab_background", colors["inactive_tab_bg"]),
                "active_tab_bg": theme_colors.get("active_tab_background", colors["active_tab_bg"])
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
inactive_tab_fg = as_rgb(hex_to_rgb_int(_colors["inactive_tab_fg"]))
active_tab_fg = as_rgb(hex_to_rgb_int(_colors["active_tab_fg"]))
inactive_tab_bg = as_rgb(hex_to_rgb_int(_colors["inactive_tab_bg"]))
active_tab_bg = as_rgb(hex_to_rgb_int(_colors["active_tab_bg"]))

def refresh_colors():
    """Refresh colors from wallbash config - only if file has changed."""
    global icon_fg, icon_bg, bat_text_color, clock_color, sep_color, utc_color, inactive_tab_fg, active_tab_fg, inactive_tab_bg, active_tab_bg, _last_mtime
    
    try:
        current_mtime = THEME_CONFIG_PATH.stat().st_mtime if THEME_CONFIG_PATH.exists() else None
        
        # Only reload if file has changed
        if current_mtime != _last_mtime:
            _last_mtime = current_mtime
            
            colors = load_wallbash_colors()
            icon_fg = as_rgb(hex_to_rgb_int(colors["icon_fg"]))
            icon_bg = as_rgb(hex_to_rgb_int(colors["icon_bg"]))
            bat_text_color = as_rgb(hex_to_rgb_int(colors["bat_text"]))
            clock_color = as_rgb(hex_to_rgb_int(colors["clock"]))
            sep_color = as_rgb(hex_to_rgb_int(colors["separator"]))
            utc_color = as_rgb(hex_to_rgb_int(colors["utc"]))
            inactive_tab_fg = as_rgb(hex_to_rgb_int(colors["inactive_tab_fg"]))
            active_tab_fg = as_rgb(hex_to_rgb_int(colors["active_tab_fg"]))
            inactive_tab_bg = as_rgb(hex_to_rgb_int(colors["inactive_tab_bg"]))
            active_tab_bg = as_rgb(hex_to_rgb_int(colors["active_tab_bg"]))
    except (OSError, ValueError):
        pass

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
    screen.cursor.italic = False
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
    # Refresh colors before drawing
    refresh_colors()
    
    if draw_data.leading_spaces:
        screen.draw(" " * draw_data.leading_spaces)

    # Save original colors
    orig_fg = screen.cursor.fg
    orig_bg = screen.cursor.bg
    
    # Set tab colors based on active/inactive state  
    if tab.is_active:
        screen.cursor.fg = active_tab_fg
        screen.cursor.bg = 0
        screen.cursor.italic = True
    else:
        screen.cursor.fg = inactive_tab_fg
        screen.cursor.bg = 0
    
    # Draw icon
    if tab.is_active:
        screen.draw("  ")
    else:
        screen.draw("  ")
    
    # Draw index and title
    title = tab.title
    if len(title) > 25:
        title_display = f"{title[:6]}…{title[-6:]}"
    else:
        title_display = title
        
    screen.draw(f"{index}:{title_display}")
    
    # Add stack indicator if needed
    if hasattr(tab, 'layout_name') and tab.layout_name == 'stack':
        screen.draw(" []")
    
    screen.draw(" ")
    
    # Restore original colors
    screen.cursor.fg = orig_fg
    screen.cursor.bg = orig_bg
    
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

    separator = " ⋮ " # alt: ⋮
    clock = datetime.now().strftime("%H:%M")
    utc = datetime.now(timezone.utc).strftime(" (%H:%M)")
    date = datetime.now().strftime("%a, %B %y")
    cells = []

    cells.append((utc_color, date))
    # cells.append((sep_color, separator))
    # cells.append((icon_fg, clock))

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
