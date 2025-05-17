import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone

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

ICON = " 󰙝 "
RIGHT_MARGIN = 1
REFRESH_TIME = 15
ADD_TAB_BUTTON = " + "  # New tab button

# Global variable to track active layout name for status display
active_layout_name = " [STACK] "  # Default value

icon_fg = as_rgb(color_as_int(Color(255, 250, 205)))
icon_bg = as_rgb(color_as_int(Color(47, 61, 68)))
bat_text_color = as_rgb(0x999F93)
clock_color = as_rgb(0x7FBBB3)
sep_color = as_rgb(0x999F93)
utc_color = as_rgb(color_as_int(Color(113, 115, 116)))

def calc_draw_spaces(*args) -> int:
    length = 0
    for i in args:
        if not isinstance(i, str):
            i = str(i)
        length += len(i)
    return length

def _draw_icon(screen: Screen, index: int, tab_bar_data: TabBarData) -> int:
    # Draw the icon regardless of total tab count, but only for the first tab
    if index != 1:
        return 0
    
    tab = get_boss().tab_for_id(tab_bar_data.tab_id)
    session_name: str = ''
    if type(get_os_window_title(tab.os_window_id)) == str:
        session_name = ' '+get_os_window_title(tab.os_window_id)+' '
    
    fg, bg = screen.cursor.fg, screen.cursor.bg
    
    # Set cursor to absolute position 0 (beginning of the tab bar)
    screen.cursor.x = 0
    
    screen.cursor.fg = icon_fg
    screen.cursor.bg = icon_bg
    screen.draw(ICON)
    screen.draw(session_name)
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.x = len(ICON) + len(session_name)
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

def _draw_right_status(screen: Screen, is_last: bool, layout_name: str) -> int:
    # Only draw for the last tab
    if not is_last:
        return 0

    draw_attributed_string(Formatter.reset, screen)
    
    # Save original cursor properties
    fg, bg = screen.cursor.fg, screen.cursor.bg
    bold, italic = screen.cursor.bold, screen.cursor.italic

    clock = datetime.now().strftime("%H:%M")

    cells = []
    cells.append((clock_color, clock))

    right_status_length = RIGHT_MARGIN
    for cell in cells:
        right_status_length += len(str(cell[1]))

    # Calculate space needed for layout button and new tab button
    layout_button_length = len(layout_name)
    new_tab_button_length = len(ADD_TAB_BUTTON)
    total_right_elements = right_status_length + layout_button_length + new_tab_button_length + 2  # +2 for padding

    # Calculate spacing - ensure positive value
    remaining_space = max(0, screen.columns - screen.cursor.x - total_right_elements)
    if remaining_space > 0:
        screen.draw(" " * remaining_space)

    # Draw clock
    for color, status in cells:
        screen.cursor.fg = color
        screen.draw(status)
    screen.draw(" ")  # Add a space before buttons
    
    # Draw layout button with a mark for clicking
    layout_start_x = screen.cursor.x
    screen.cursor.fg = as_rgb(color_as_int(Color(0, 0, 0)))  # Black text
    screen.cursor.bg = as_rgb(color_as_int(Color(140, 180, 175)))  # Light teal background
    screen.draw(layout_name)
    
    # Register clickable area for layout cycling
    screen.set_mark(layout_start_x, layout_start_x + layout_button_length, "next_layout")
    
    # Draw new tab button with distinct color
    new_tab_start_x = screen.cursor.x
    screen.cursor.fg = as_rgb(color_as_int(Color(0, 0, 0)))  # Black text
    screen.cursor.bg = as_rgb(color_as_int(Color(200, 150, 100)))  # Orange/amber background
    screen.draw(ADD_TAB_BUTTON)
    
    # Register clickable area for new tab
    screen.set_mark(new_tab_start_x, new_tab_start_x + new_tab_button_length, "new_tab")
    
    # Reset cursor properties
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.bold, screen.cursor.italic = bold, italic

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
    # Always draw the icon for the first tab, regardless of total tab count
    if index == 1:
        _draw_icon(screen, index, tab)

    global active_layout_name
    if tab.is_active:
        boss = get_boss()
        w = boss.active_window
        if w and w.overlay_parent is not None:
            lvl = 0
            while w.overlay_parent is not None:
                w = w.overlay_parent
                lvl += 1
            overlay_label = f" [OVERLAY {lvl}] "
            active_layout_name = overlay_label
        else:
            active_layout_name = f" [{tab.layout_name.upper()}] "

    end = _draw_left_status(
        draw_data,
        screen,
        tab,
        before,
        max_title_length,
        index,
        is_last,
        extra_data,
    )
    
    # Always draw the right status for the last tab
    if is_last:
        _draw_right_status(
            screen,
            is_last,
            active_layout_name
        )

    return screen.cursor.x

def handle_mouse(screen: Screen, tab_bar_data: TabBarData, event_type: int, x: int, y: int) -> int:
    # Only handle mouse click events (type 1)
    if event_type != 1:  
        return 0
    
    mark = screen.mark_at(x)
    if mark is None:
        return 0
        
    # Handle layout button click
    if mark.identifier == "next_layout":
        get_boss().active_tab.next_layout()
        return 1
    
    # Handle new tab button click
    if mark.identifier == "new_tab":
        get_boss().launch_tab()
        return 1
        
    return 0
