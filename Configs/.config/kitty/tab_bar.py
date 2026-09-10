"""Custom Kitty tab bar with live theme colors."""

# pyright: reportMissingImports=false
import os
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    from kitty.fast_data_types import Screen
    from kitty.tab_bar import (
        DrawData,
        ExtraData,
        Formatter,
        TabBarData,
        as_rgb,
        draw_attributed_string,
        get_boss,
    )
    from kitty.utils import color_as_int
except ImportError:
    Screen = DrawData = ExtraData = Formatter = TabBarData = Any  # type: ignore

    def as_rgb(value: int) -> int:  # type: ignore
        return value

    def draw_attributed_string(*args: Any) -> None:  # type: ignore
        pass

    def color_as_int(value: Any) -> int:  # type: ignore
        return 0

    def get_boss() -> Any:  # type: ignore
        return None


RIGHT_MARGIN = 1
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
COLOR_FILES = (
    CONFIG_HOME / "kitty/theme.generated.conf",
    CONFIG_HOME / "kitty/colors.conf",
)
QS_STATUS_PATH = STATE_HOME / "quickshell/time-visibility"
COLOR_MAP = {
    "icon_fg": ("foreground", "#dcd7ba"),
    "icon_bg": ("background", "#1f1f28"),
    "separator": ("color8", "#727169"),
    "utc": ("color8", "#727169"),
    "inactive_tab_fg": ("inactive_tab_foreground", "#727169"),
    "active_tab_fg": ("active_tab_foreground", "#c8c093"),
}


def _mtime(path: Path) -> int:
    try:
        return path.stat().st_mtime_ns
    except OSError:
        return 0


def _load_colors() -> dict[str, int]:
    raw: dict[str, str] = {}
    for path in COLOR_FILES:
        try:
            raw = {
                parts[0]: parts[1]
                for line in path.read_text().splitlines()
                if line and not line.lstrip().startswith("#")
                and len(parts := line.split()) >= 2
            }
        except OSError:
            continue
        if raw:
            break
    return {
        name: as_rgb(int(raw.get(source, fallback).lstrip("#"), 16))
        for name, (source, fallback) in COLOR_MAP.items()
    }


_colors = _load_colors()
_color_mtimes = tuple(map(_mtime, COLOR_FILES))
_qs_status_mtime = 0
_qs_status = (0, False, False)


def _refresh_colors() -> None:
    global _colors, _color_mtimes
    mtimes = tuple(map(_mtime, COLOR_FILES))
    if mtimes != _color_mtimes:
        _color_mtimes = mtimes
        try:
            _colors = _load_colors()
        except ValueError:
            pass


def _active_window_bg() -> int:
    try:
        window = get_boss().active_window
        if window is not None:
            return as_rgb(color_as_int(window.screen.color_profile.default_bg))
    except Exception:
        pass
    return _colors["icon_bg"]


def _quickshell_visibility() -> tuple[bool, bool]:
    global _qs_status_mtime, _qs_status
    try:
        mtime = QS_STATUS_PATH.stat().st_mtime_ns
        if mtime != _qs_status_mtime:
            pid, date, clock = QS_STATUS_PATH.read_text().split()
            _qs_status_mtime, _qs_status = mtime, (int(pid), date == "1", clock == "1")
        return _qs_status[1:] if Path(f"/proc/{_qs_status[0]}").exists() else (False, False)
    except (OSError, ValueError):
        return False, False


def _draw_icon(screen: Screen, index: int, layout: str) -> None:
    if index != 1:
        return
    fg, bg = screen.cursor.fg, screen.cursor.bg
    screen.cursor.fg = _colors["icon_fg"]
    screen.cursor.bg = _active_window_bg()
    screen.cursor.italic = False
    screen.cursor.bold = True
    text = f" 󱚠 {layout.upper()} "
    screen.draw(text)
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.x = len(text)


def _draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
) -> int:
    if draw_data.leading_spaces:  # type: ignore
        screen.draw(" " * draw_data.leading_spaces)  # type: ignore
    fg, bg = screen.cursor.fg, screen.cursor.bg
    screen.cursor.fg = _colors["active_tab_fg" if tab.is_active else "inactive_tab_fg"]  # type: ignore
    screen.cursor.bg = 0
    screen.cursor.italic = tab.is_active  # type: ignore
    screen.draw("  " if tab.is_active else "  ")  # type: ignore
    title = tab.title  # type: ignore
    screen.draw(f"{index}:{title[:6]}…{title[-6:]}" if len(title) > 25 else f"{index}:{title}")
    if getattr(tab, "layout_name", "") == "stack":
        screen.draw(" []")
    screen.draw(" ")

    trailing = min(max_title_length - 1, draw_data.trailing_spaces)  # type: ignore
    extra = screen.cursor.x - before - (max_title_length - trailing)
    if extra > 0:
        screen.cursor.x -= extra + 1
        screen.draw("…")
    if trailing:
        screen.draw(" " * trailing)
    end = screen.cursor.x
    screen.cursor.bold = screen.cursor.italic = False
    screen.cursor.fg = 0
    if not is_last:
        screen.cursor.bg = as_rgb(color_as_int(draw_data.inactive_bg))  # type: ignore
        screen.draw(draw_data.sep)  # type: ignore
    screen.cursor.fg, screen.cursor.bg = fg, bg
    return end


def _draw_right_status(screen: Screen, is_last: bool) -> None:
    if not is_last:
        return
    draw_attributed_string(Formatter.reset, screen)  # type: ignore
    now = datetime.now()
    hide_date, hide_clock = _quickshell_visibility()
    cells = []
    if not hide_clock:
        cells.append((_colors["icon_fg"], now.strftime("%H:%M")))
    if not hide_clock and not hide_date:
        cells.append((_colors["separator"], " "))
    if not hide_date:
        cells.append((_colors["utc"], now.strftime(" %a,%b.%d " if hide_clock else "(%a,%b.%d)")))

    length = RIGHT_MARGIN + sum(len(text) for _, text in cells)
    spaces = screen.columns - screen.cursor.x - length
    if spaces > 0:
        screen.draw(" " * spaces)
    for color, text in cells:
        screen.cursor.fg = color
        screen.draw(text)
    screen.cursor.fg = screen.cursor.bg = 0


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
        _refresh_colors()
    _draw_icon(screen, index, getattr(tab, "layout_name", "unknown"))
    end = _draw_tab(draw_data, screen, tab, before, max_title_length, index, is_last)
    _draw_right_status(screen, is_last)
    return end
