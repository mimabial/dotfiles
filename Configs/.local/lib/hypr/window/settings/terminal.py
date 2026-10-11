import curses
import curses.ascii
import os
from decimal import Decimal
import subprocess
import sys

from .events import SettingsEvents
from .visual import VisualSettings

HINT = "↑↓ row   ←→ adjust   Space toggle   Tab section   Backspace reset   q close"


PAIR_ACCENT = 1
PAIR_DIM = 2
PAIR_ERROR = 3
PAIR_BAR = 4
BRIGHT_BLACK = 8

SECTION_WIDTH = 18
VALUE_WIDTH = 5
ROW_PITCH = 2
MIN_HEIGHT = 6
MIN_WIDTH = 40
STATUS_MIN_X = 14
MIN_FLOAT_DECIMALS = 2
MIN_LABEL_WIDTH = 12
LABEL_WIDTH_SHARE = 0.42
MIN_CONTROL_WIDTH = 4


def initialize_terminal_colors():
    curses.start_color()
    curses.use_default_colors()
    accent = curses.COLOR_BLUE
    dim = BRIGHT_BLACK if curses.COLORS > BRIGHT_BLACK else curses.COLOR_WHITE
    curses.init_pair(PAIR_ACCENT, accent, -1)
    curses.init_pair(PAIR_DIM, dim, -1)
    curses.init_pair(PAIR_ERROR, curses.COLOR_RED, -1)
    curses.init_pair(PAIR_BAR, curses.COLOR_CYAN, -1)


def value_text(row, value):
    if value is None:
        return "—"
    if row["type"] == "float":
        step_decimals = -Decimal(str(row.get("step") or 1)).as_tuple().exponent
        return "%.*f" % (max(MIN_FLOAT_DECIMALS, step_decimals), float(value))
    if row["type"] == "bool":
        return "on" if value is True else "off"
    return str(value)


def slider_gauge(row, value, width):
    """A slider still reads as a slider in a terminal; the fill is the fraction
    of the row's own min..max range."""
    try:
        fraction = (float(value) - row["min"]) / (row["max"] - row["min"])
    except (TypeError, ValueError, ZeroDivisionError):
        fraction = 0.0
    fraction = min(1.0, max(0.0, fraction))
    filled = int(round(fraction * width))
    return "█" * filled + "░" * (width - filled)


def write_clipped_text(window, y, x, text, attr=0, limit=None):
    height, width = window.getmaxyx()
    if y < 0 or y >= height or x >= width:
        return
    room = width - x - 1
    if limit is not None:
        room = min(room, limit)
    if room <= 0:
        return
    try:
        window.addstr(y, x, text[:room], attr)
    except curses.error:
        pass


def scrolled_offset(offset, index, visible):
    if index < offset:
        return index
    if index >= offset + visible:
        return index - visible + 1
    return offset


def draw_header(window, settings, width, accent, dim):
    write_clipped_text(window, 0, 1, getattr(settings, "title", "Look & Feel"), accent | curses.A_BOLD)
    status = settings.theme_key
    write_clipped_text(window, 0, max(STATUS_MIN_X, width - len(status) - 2), status, dim)
    write_clipped_text(window, 1, 1, "─" * (width - 2), dim)


def draw_sections(window, settings, top, bottom, accent, dim):
    sections = settings.sections
    visible = bottom - top
    first = scrolled_offset(getattr(settings, "section_offset", 0), settings.section_index, visible)
    settings.section_offset = first
    for index in range(first, min(len(sections), first + visible)):
        selected = index == settings.section_index
        attr = (accent | curses.A_BOLD) if selected else dim
        marker = "▌" if selected else " "
        write_clipped_text(window, top + index - first, 1, marker + " " + sections[index]["title"], attr, limit=SECTION_WIDTH)
    for y in range(top, bottom):
        write_clipped_text(window, y, SECTION_WIDTH + 1, "│", dim)


def draw_control(window, settings, row, value, y, x, room, selected, accent, dim):
    text = value_text(row, value)
    if row["type"] in ("int", "float"):
        bar_width = max(MIN_CONTROL_WIDTH, room - VALUE_WIDTH - 1)
        write_clipped_text(window, y, x, slider_gauge(row, value, bar_width), accent if selected else dim)
        write_clipped_text(window, y, x + bar_width + 1, text.rjust(VALUE_WIDTH), 0 if selected else dim)
    elif row["type"] == "bool":
        write_clipped_text(window, y, x, "[x]" if value is True else "[ ]", accent if selected else 0)
    else:
        pending = row["type"] == "pipeline" and row["id"] == settings.pipeline_pending_id
        shown = "‹ %s ›" % text if selected else "  %s" % text
        write_clipped_text(window, y, x, shown + (" …" if pending else ""), accent if selected else 0, limit=room)


def draw_rows(window, settings, top, bottom, width, accent, dim):
    rows = settings.active_rows
    rows_x = SECTION_WIDTH + 2
    visible = max(1, (bottom - top + ROW_PITCH - 1) // ROW_PITCH)
    settings.row_offset = scrolled_offset(settings.row_offset, settings.row_index, visible)
    label_width = max(MIN_LABEL_WIDTH, int((width - rows_x) * LABEL_WIDTH_SHARE))
    control_x = rows_x + 1 + label_width
    room = width - control_x - 2
    for index in range(settings.row_offset, min(len(rows), settings.row_offset + visible)):
        row = rows[index]
        y = top + (index - settings.row_offset) * ROW_PITCH
        selected = index == settings.row_index
        value = settings.value_for(row)
        if settings.is_overridden(row):
            write_clipped_text(window, y, rows_x - 1, "▌", curses.color_pair(PAIR_BAR))
        write_clipped_text(window, y, rows_x + 1, row["label"], (accent | curses.A_BOLD) if selected else 0, limit=label_width)
        if room > MIN_CONTROL_WIDTH:
            draw_control(window, settings, row, value, y, control_x, room, selected, accent, dim)


def draw_footer(window, settings, height, dim):
    footer = height - 1
    if settings.error_text:
        write_clipped_text(window, footer, 1, settings.error_text.replace("\n", " "), curses.color_pair(PAIR_ERROR))
    else:
        write_clipped_text(window, footer, 1, getattr(settings, "hint", HINT), dim)


def draw_settings(window, settings):
    window.erase()
    height, width = window.getmaxyx()
    if height < MIN_HEIGHT or width < MIN_WIDTH:
        write_clipped_text(window, 0, 0, "terminal too small")
        window.noutrefresh()
        return

    accent = curses.color_pair(PAIR_ACCENT)
    dim = curses.color_pair(PAIR_DIM)
    top, bottom = 2, height - 2
    draw_header(window, settings, width, accent, dim)
    draw_sections(window, settings, top, bottom, accent, dim)
    draw_rows(window, settings, top, bottom, width, accent, dim)
    draw_footer(window, settings, height, dim)
    window.noutrefresh()


class TerminalInput:
    def __init__(self, window):
        self.window = window

    def run_program(self, command):
        curses.def_prog_mode()
        curses.endwin()
        try:
            code = subprocess.run(command, check=False).returncode
        finally:
            curses.reset_prog_mode()
            curses.curs_set(0)
            self.window.keypad(True)
            self.window.timeout(0)
            self.window.clear()
        return code

    def read_answer(self, label):
        window = self.window
        height, width = window.getmaxyx()
        window.move(height - 1, 0)
        window.clrtoeol()
        window.addstr(height - 1, 1, label[:width - 3])
        window.refresh()
        curses.echo()
        curses.curs_set(1)
        window.timeout(-1)
        try:
            return window.getstr(height - 1, min(width - 2, len(label) + 1),
                              max(1, width - len(label) - 3)).decode(errors="replace")
        finally:
            window.timeout(0)
            curses.noecho()
            curses.curs_set(0)


def run_settings(window, settings_type=VisualSettings):
    curses.curs_set(0)
    initialize_terminal_colors()
    window.keypad(True)
    window.timeout(0)

    settings = settings_type()
    events = SettingsEvents()
    settings.events = events
    settings.terminal = TerminalInput(window)
    try:
        events.watch_files((settings.theme_path, settings.staterc_path, settings.variant_path), settings.handle_state_change)
        events.watch_input(sys.stdin.fileno())
        def resize_terminal():
            size = os.get_terminal_size(sys.stdin.fileno())
            curses.resizeterm(size.lines, size.columns)
        events.watch_resize(resize_terminal)
        settings.refresh()

        while True:
            draw_settings(window, settings)
            curses.doupdate()
            key = window.getch()

            if key == -1:
                events.wait()
                continue

            if hasattr(settings, "handle_key") and settings.handle_key(key):
                settings.save_pending_changes()
                continue

            rows = settings.active_rows
            row = rows[settings.row_index] if 0 <= settings.row_index < len(rows) else None

            # Not ESC: ncurses cannot tell a bare Escape from the first byte of an
            # escape sequence, so it holds it for ESCDELAY (1s by default) and
            # closing looked like a hang.
            if key == ord("q"):
                break
            elif key in (curses.KEY_UP, ord("k")):
                settings.move_row(-1)
            elif key in (curses.KEY_DOWN, ord("j")):
                settings.move_row(1)
            elif key in (curses.KEY_LEFT, ord("h")):
                if row:
                    settings.adjust(row, -1)
            elif key in (curses.KEY_RIGHT, ord("l")):
                if row:
                    settings.adjust(row, 1)
            elif key == ord("\t"):
                settings.move_section(1)
            elif key == curses.KEY_BTAB:
                settings.move_section(-1)
            elif key in (ord(" "), curses.KEY_ENTER, curses.ascii.NL, curses.ascii.CR):
                if row and row["type"] == "bool":
                    settings.toggle_row(row)
                elif row:
                    settings.adjust(row, 1)
            elif key in (curses.KEY_BACKSPACE, curses.ascii.DEL, curses.ascii.BS):
                if row:
                    settings.reset_row(row)
            elif key == curses.KEY_RESIZE:
                pass

            settings.save_pending_changes()

    finally:
        try:
            settings.save_pending_changes()
        finally:
            events.close()
