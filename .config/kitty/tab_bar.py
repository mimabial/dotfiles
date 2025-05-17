import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone

from kitty.boss import get_boss
from kitty.fast_data_types import Screen, add_timer, get_os_window_title, set_tab_bar_render_data
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

LAYOUTS = ["stack", "tall", "fat", "grid", "horizontal", "vertical", "splits"]
NEW_TAB_BUTTON = " + "
layout_color = as_rgb(0xD8A657)
new_tab_color = as_rgb(0xA9B665)

# Global variable to track active layout name for status display
active_layout_name = ""

icon_fg = as_rgb(color_as_int(Color(255, 250, 205)))
icon_bg = as_rgb(color_as_int(Color(47, 61, 68)))
bat_text_color = as_rgb(0x999F93)
clock_color = as_rgb(0x7FBBB3)
layout_color = as_rgb(0x87c095)  # Green color for layout indicator
new_tab_color = as_rgb(0xe67e80)  # Red color for new tab button
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
    if index != 1:
        return 0
    tab = get_boss().tab_for_id(tab_bar_data.tab_id)
    session_name: str = ''
    if type(get_os_window_title(tab.os_window_id)) == str:
        session_name = ' '+get_os_window_title(tab.os_window_id)+' '
    fg, bg = screen.cursor.fg, screen.cursor.bg
    screen.cursor.fg = icon_fg
    screen.cursor.bg = icon_bg
    screen.draw(ICON)
    screen.draw(session_name)
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.x = len(ICON) + len(session_name)
    return screen.cursor.x

def draw_session_name(draw_data: DrawData, screen: Screen, tab_bar_data: TabBarData, index: int) -> int:
    tab = get_boss().tab_for_id(tab_bar_data.tab_id)
    session_name: str = ' '+get_os_window_title(tab.os_window_id)+' '

    fg, bg, bold, italic = (
        screen.cursor.fg,
        screen.cursor.bg,
        screen.cursor.bold,
        screen.cursor.italic,
    )

    screen.cursor.bold, screen.cursor.italic = (True, True)
    colorfg = as_rgb(color_as_int(opts.color4))
    colorbg = as_rgb(color_as_int(opts.color0))

    screen.cursor.fg, screen.cursor.bg = (
        colorbg,
        colorfg,
    )  # inverted colors for high contrast
    screen.draw(f"{session_name}")

    screen.cursor.x = len(session_name) + 1

    # set cursor position
    # restore color style
    screen.cursor.fg, screen.cursor.bg, screen.cursor.bold, screen.cursor.italic = (
        fg,
        bg,
        bold,
        italic,
    )
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
    # print(extra_data)
    if draw_data.leading_spaces:
        screen.draw(" " * draw_data.leading_spaces)

    # TODO: https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-2463083
    # tm = get_boss().active_tab_manager
    #     if tm is not None:
    #         w = tm.active_window
    #         if w is not None:
    #             cwd = w.cwd_of_child or ''
    #             log_error(cwd)

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

# more handy kitty tab_bar things:
# REF: https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-2183440
def _draw_right_status(screen: Screen, is_last: bool, layout_name: str) -> int:
    if not is_last:
        return 0
    # global timer_id
    # if timer_id is None:
    #     timer_id = add_timer(_redraw_tab_bar, REFRESH_TIME, True)

    draw_attributed_string(Formatter.reset, screen)

    clock = datetime.now().strftime("%H:%M  %y-%m-%d ")
    # utc = datetime.now(timezone.utc).strftime(" (UTC %H:%M)")

    cells = []

    cells.append((clock_color, clock))
    # cells.append((utc_color, utc))

    layout_name_length = len(layout_name.strip().replace('[', '').replace(']', '')) + 2  # +2 for spacing
    right_status_length = RIGHT_MARGIN + len(NEW_TAB_BUTTON) + layout_name_length
    for cell in cells:
        right_status_length += len(str(cell[1]))

    draw_spaces = screen.columns - screen.cursor.x - right_status_length

    if draw_spaces > 0:
        screen.draw(" " * draw_spaces)

    # Draw the layout button first
    _draw_layout_button(screen, is_last, layout_name)
    
    # Then draw the new tab button
    _draw_new_tab_button(screen, is_last)
    
    # Finally draw the clock
    screen.cursor.fg = 0
    for color, status in cells:
        screen.cursor.fg = color  # as_rgb(color_as_int(color))
        screen.draw(status)
    screen.cursor.bg = 0

    if screen.columns - screen.cursor.x > right_status_length:
        screen.cursor.x = screen.columns - right_status_length

    return screen.cursor.x

def _draw_layout_button(screen: Screen, is_last: bool, layout_name: str) -> int:
    if not is_last:
        return 0
        
    # Strip brackets from layout name for display
    clean_layout = layout_name.strip().replace('[', '').replace(']', '')
    
    # Mark the region as clickable
    start_x = screen.cursor.x
    
    # Draw the layout button
    screen.cursor.fg = layout_color
    screen.draw(f" {clean_layout} ")
    
    # Register marker for click action to cycle layouts
    screen.set_marker(1, start_x, screen.cursor.x - 1)
    
    return screen.cursor.x

def _draw_new_tab_button(screen: Screen, is_last: bool) -> int:
    if not is_last:
        return 0
        
    # Mark the region as clickable
    start_x = screen.cursor.x
    
    # Draw the new tab button
    screen.cursor.fg = new_tab_color
    screen.draw(NEW_TAB_BUTTON)
    
    # Register marker for click action to create new tab
    screen.set_marker(2, start_x, screen.cursor.x - 1)
    
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
    if index == 1:
        _draw_icon(screen, index, tab)

    global active_layout_name
    current_layout = ""
    
    if tab.is_active:
        boss = get_boss()
        w = boss.active_window
        if w.overlay_parent is not None:
            lvl = 0
            while w.overlay_parent is not None:
                w = w.overlay_parent
                lvl += 1
            overlay_label = f" [Overlay {lvl}] "
            active_layout_name = overlay_label
        else:
            active_layout_name = f"{tab.layout_name.upper()}"
        current_layout = active_layout_name

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
    
    if is_last and active_layout_name != "":
        _draw_right_status(
            screen,
            is_last,
            current_layout,
        )

    return screen.cursor.x

def handle_mouse(screen: Screen, tab_id: int, x: int, button: int) -> bool:
    marker = screen.marker_from_position(x)
    if marker is None:
        return False
        
    if marker.id == 1:  # Layout button was clicked
        boss = get_boss()
        tab = boss.tab_for_id(tab_id)
        if tab:
            # Get current layout index
            current_layout = tab.current_layout.name
            try:
                idx = LAYOUTS.index(current_layout)
                # Cycle to next layout
                next_idx = (idx + 1) % len(LAYOUTS)
                next_layout = LAYOUTS[next_idx]
                # Change the layout
                tab.goto_layout(next_layout)
            except ValueError:
                # If current layout not in list, go to first one
                tab.goto_layout(LAYOUTS[0])
        return True
        
    if marker.id == 2:  # New tab button was clicked
        boss = get_boss()
        # Create a new tab
        boss.create_tab(tab_type="", cwd_from=None)
        return True
        
    return False
