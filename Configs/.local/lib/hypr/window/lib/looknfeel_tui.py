#!/usr/bin/env python3
"""Terminal UI for the visual half of the Hyprland config: read current values,
preview live while adjusting, and persist per theme.

Colours come from the terminal palette, which the theme pipeline already writes
through render/kitty.sh, so no palette is plumbed in here.

Read paths and the storage contract are documented in
../LOOKNFEEL.md.
"""

import curses
import math
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import looknfeel_lua as lua  # noqa: E402
import looknfeel_schema as schema  # noqa: E402

HOME = Path.home()
LIB_DIR = Path(os.environ.get("HYPR_LIB_DIR") or HOME / ".local/lib/hypr")
STATE_DIR = Path(os.environ.get("HYPR_STATE_HOME") or HOME / ".local/state/hypr")
CONFIG_DIR = Path(os.environ.get("HYPR_CONFIG_HOME") or HOME / ".config/hypr")
HYPRSHELL = str(HOME / ".local/bin/hyprshell")
READER = str(LIB_DIR / "window/looknfeel-read.lua")

PERSIST_DELAY = 0.25
RELOAD_DELAY = 0.30
CURSOR_PREVIEW_DELAY = 0.04
CURSOR_SYNC_DELAY = 0.70
WATCH_INTERVAL = 0.25

HINT = "↑↓ row   ←→ adjust   Space toggle   Tab section   Backspace reset   q close"


def js_round(value):
    """JS Math.round rounds halves toward +inf; Python's round() is banker's."""
    return math.floor(value + 0.5)


def round_to(value, digits):
    scale = 10 ** digits
    return js_round(value * scale) / scale


def slug(name):
    """Lua patterns are ASCII-only; looknfeel.lua slugs identically so the TUI
    writes where the resolver reads."""
    out = re.sub(r"[^a-z0-9]+", "-", str(name or "default").lower())
    return out.strip("-")


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def read_text(path):
    try:
        return Path(path).read_text()
    except OSError:
        return ""


def mtime(path):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return 0.0


class Looknfeel:
    def __init__(self):
        self.current = {}
        self.theme_defaults = {}
        self.variable_defaults = {}
        self.overrides = {}
        self.variable_overrides = {}
        self.baseline_animations = []
        self.speed_multiplier = 1
        self.engine = "master"
        self.variant = "dark"
        self.theme_name = ""
        self.section_index = 0
        self.row_index = 0
        self.row_offset = 0
        self.error_text = ""
        self.pipeline_options = {}
        self.pipeline_current = {}
        self.pipeline_pending_id = ""
        self.pipeline_pending_value = None

        self._deadlines = {}
        self._list_procs = []
        self._async = []
        self._cursor_persist_pending = False
        self._watched = {}

        self.theme_path = CONFIG_DIR / "themes/theme.lua"
        self.staterc_path = STATE_DIR / "staterc"
        self.variant_path = STATE_DIR / "color_variant"

    @property
    def theme_key(self):
        return slug(self.theme_name) + "." + self.variant

    @property
    def override_path(self):
        return STATE_DIR / "looknfeel.d" / (self.theme_key + ".lua")

    @property
    def sections(self):
        """The Layout section shows only the active engine's knobs. Every
        engine's keys resolve regardless of general:layout, so this is
        presentation only."""
        out = []
        for section in schema.sections():
            rows = section["rows"]
            if section["title"] == "Layout":
                rows = rows + schema.layout_rows(self.engine)
            out.append({"title": section["title"], "rows": rows})
        return out

    @property
    def active_rows(self):
        sections = self.sections
        if 0 <= self.section_index < len(sections):
            return sections[self.section_index]["rows"]
        return []

    def refresh(self):
        keys = list(schema.query_keys())
        for engine in schema.ENGINES:
            keys += [row["key"] for row in schema.layout_rows(engine)]
        batch = " ; ".join("getoption " + key for key in keys)
        proc = run(["hyprctl", "-j", "--batch", batch])
        self.current = lua.parse_getoption(proc.stdout)
        layout = self.current.get("general:layout")
        if layout and layout.get("value"):
            self.engine = str(layout["value"])

        self.read_state_files()
        self.read_block()
        self.read_baseline()
        self.start_option_lists()

    def read_block(self):
        proc = run(["lua", READER, str(self.override_path)])
        if proc.returncode != 0:
            # A missing file is the normal case for a theme with no overrides
            # yet; the reader exits non-zero on it, which is not an error here.
            self.overrides = {}
            self.variable_overrides = {}
            self.speed_multiplier = 1
            return
        parsed = lua.parse_records(proc.stdout)
        self.overrides = parsed["keys"]
        self.variable_overrides = parsed["variables"]
        self.speed_multiplier = self.derive_multiplier(parsed["animations"])

    def read_baseline(self):
        proc = run(["lua", READER, str(STATE_DIR / "animations.lua")])
        if proc.returncode == 0:
            self.baseline_animations = lua.parse_records(proc.stdout)["animations"]

    def read_state_files(self):
        theme_text = read_text(self.theme_path)
        self.theme_defaults = lua.parse_theme_config(theme_text)
        self.variable_defaults = lua.parse_theme_variables(theme_text)

        raw = read_text(self.staterc_path)
        self.theme_name = self.state_value(raw, "HYPR_THEME", "")
        self.pipeline_current = {
            "animation_preset": self.state_value(raw, "HYPR_ANIMATION", "default"),
            "shader": self.state_value(raw, "HYPR_SHADER", "neutral"),
            "workflow": self.state_value(raw, "HYPR_WORKFLOW", "default"),
        }
        if (self.pipeline_pending_id
                and str(self.pipeline_current.get(self.pipeline_pending_id))
                == str(self.pipeline_pending_value)):
            self.pipeline_pending_id = ""

        self.variant = "light" if read_text(self.variant_path).strip() == "light" else "dark"
        self._watched = {path: mtime(path) for path in
                         (self.theme_path, self.staterc_path, self.variant_path)}

    @staticmethod
    def state_value(raw, name, fallback):
        match = re.search(r'(?:^|\n)%s=["\']?([^"\'\n]+)' % name, raw)
        return match.group(1) if match else fallback

    def watched_changed(self):
        return any(mtime(path) != stamp for path, stamp in self._watched.items())

    def derive_multiplier(self, written):
        """The multiplier is stored implicitly: scaled speeds are what land in
        the file, so it is recovered by comparing against the active preset."""
        if not written:
            return 1
        for base in self.baseline_animations:
            for leaf in written:
                if leaf["leaf"] == base["leaf"] and base["speed"] > 0:
                    return round_to(leaf["speed"] / base["speed"], 2)
        return 1

    def start_option_lists(self):
        for row in schema.listed_rows():
            proc = subprocess.Popen(
                [HYPRSHELL] + list(row["list"]),
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
            )
            self._list_procs.append((row["id"], proc))

    def harvest_option_lists(self):
        changed = False
        for entry in list(self._list_procs):
            row_id, proc = entry
            if proc.poll() is None:
                continue
            out = proc.stdout.read() if proc.stdout else ""
            if proc.stdout:
                proc.stdout.close()
            self.pipeline_options[row_id] = [
                line.split("\t")[0] for line in out.splitlines() if line
            ]
            self._list_procs.remove(entry)
            changed = True
        return changed

    def set_pipeline(self, row, name):
        self.pipeline_pending_value = name
        self.pipeline_pending_id = row["id"]
        self.spawn([HYPRSHELL] + list(row["set"]) + [name], on_exit=self.pipeline_done)

    def pipeline_done(self, code):
        if code == 0:
            self.read_state_files()
        else:
            self.pipeline_pending_id = ""
            self.error_text = "could not apply " + str(self.pipeline_pending_value)

    def arm(self, name, delay):
        self._deadlines[name] = time.monotonic() + delay

    def due(self, name):
        deadline = self._deadlines.get(name)
        if deadline is not None and time.monotonic() >= deadline:
            del self._deadlines[name]
            return True
        return False

    def pending(self, name):
        return name in self._deadlines

    def spawn(self, command, on_exit=None):
        proc = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        self._async.append((proc, on_exit))

    def harvest_async(self):
        changed = False
        for entry in list(self._async):
            proc, on_exit = entry
            code = proc.poll()
            if code is None:
                continue
            self._async.remove(entry)
            if on_exit:
                on_exit(code)
            changed = True
        return changed

    def value_for(self, row):
        if row["type"] == "pipeline":
            if row["id"] == self.pipeline_pending_id:
                return self.pipeline_pending_value
            return self.pipeline_current.get(row["id"])
        if row.get("id") == "animation_speed":
            return self.speed_multiplier
        if row.get("variable"):
            if row["variable"] in self.variable_overrides:
                return self.variable_overrides[row["variable"]]
            return self.variable_defaults.get(row["variable"])
        if row["key"] in self.overrides:
            return self.overrides[row["key"]]
        live = self.current.get(row["key"])
        return live["value"] if live else None

    def is_overridden(self, row):
        if row.get("id") == "animation_speed":
            return self.speed_multiplier != 1
        if row["type"] == "pipeline":
            return False
        if row.get("variable"):
            return row["variable"] in self.variable_overrides
        return row["key"] in self.overrides

    def baseline_for(self, row):
        """Dialling a row back to what the theme asks for is the same as
        resetting it, so drop the key rather than emitting Lua that restates the
        theme. The theme file is the reference; the live read is the fallback
        for keys it leaves to Hyprland's own defaults."""
        if row.get("variable"):
            return self.variable_defaults.get(row["variable"])
        if row["key"] in self.theme_defaults:
            return self.theme_defaults[row["key"]]
        live = self.current.get(row["key"])
        return live["value"] if live else None

    def matches_baseline(self, row, value):
        baseline = self.baseline_for(row)
        if baseline is None:
            return False
        if row["type"] == "bool":
            return bool(baseline) == bool(value)
        if row["type"] in ("int", "float"):
            try:
                return abs(float(baseline) - float(value)) < 1e-6
            except (TypeError, ValueError):
                return False
        return str(baseline) == str(value)

    def render_current(self):
        animations = []
        if self.speed_multiplier != 1:
            for leaf in self.baseline_animations:
                animations.append({
                    "leaf": leaf["leaf"],
                    "enabled": leaf["enabled"],
                    "speed": max(0.1, round_to(leaf["speed"] * self.speed_multiplier, 2)),
                    "bezier": leaf["bezier"],
                    "style": leaf["style"],
                })
        return lua.render_block(self.overrides, animations, self.variable_overrides)

    def set_override(self, row, value):
        if row.get("variable"):
            if row["type"] == "int":
                value = js_round(value)
            if self.matches_baseline(row, value):
                self.variable_overrides.pop(row["variable"], None)
            else:
                self.variable_overrides[row["variable"]] = str(value)
            self._cursor_persist_pending = True
            self.arm("cursor_preview", CURSOR_PREVIEW_DELAY)
            self.apply_preview()
            return
        if row["type"] == "int":
            value = js_round(value)
        if self.matches_baseline(row, value):
            self.overrides.pop(row["key"], None)
        else:
            self.overrides[row["key"]] = value
        self.apply_preview()

    def reset_row(self, row):
        """Reset drops the key so the emitted Lua disappears and the theme's
        value returns on reload. No default is ever stored."""
        if row.get("id") == "animation_speed":
            self.speed_multiplier = 1
        elif row.get("variable"):
            self.variable_overrides.pop(row["variable"], None)
            self._cursor_persist_pending = True
            self.arm("cursor_preview", CURSOR_PREVIEW_DELAY)
        elif row["type"] != "pipeline":
            self.overrides.pop(row["key"], None)
        self.apply_preview()
        if not row.get("variable"):
            # A cleared key only comes back on reload, since eval cannot un-set
            # one.
            self.arm("reload", RELOAD_DELAY)

    def apply_preview(self):
        block = self.render_current()
        if block:
            # The separator matters: the block opens with a fence comment and
            # hyprctl parses a leading `--` as a flag.
            run(["hyprctl", "eval", "--", block])
        self.arm("persist", PERSIST_DELAY)

    def cursor_value(self, name):
        if name in self.variable_overrides:
            return self.variable_overrides[name]
        return self.variable_defaults.get(name, "")

    def start_cursor_preview(self):
        theme = str(self.cursor_value("CURSOR_THEME"))
        try:
            size = js_round(float(self.cursor_value("CURSOR_SIZE")))
        except (TypeError, ValueError):
            return
        if not theme or size <= 0:
            return
        self.spawn(["hyprctl", "setcursor", theme, str(size)])

    def persist(self):
        block = self.render_current()
        sync_cursor = self._cursor_persist_pending
        self._cursor_persist_pending = False
        path = self.override_path
        try:
            if not block:
                path.unlink(missing_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                temporary = path.with_name(path.name + ".new")
                temporary.write_text(block)
                os.replace(temporary, path)
        except OSError:
            self.error_text = "could not write " + str(path)
            return

        errors = run(["hyprctl", "configerrors"]).stdout.strip()
        self.error_text = "" if errors in ("", "no errors") else errors
        if sync_cursor:
            self.arm("cursor_sync", CURSOR_SYNC_DELAY)

    def start_cursor_sync(self):
        self.spawn([HYPRSHELL, "theme/desktop.sync.sh", "--full", "--quiet"],
                   on_exit=self.cursor_sync_done)

    def cursor_sync_done(self, code):
        if code != 0:
            self.error_text = "could not sync cursor settings"
        elif self.error_text == "could not sync cursor settings":
            self.error_text = ""

    def flush(self):
        if self.pending("persist"):
            self._deadlines.pop("persist", None)
            self.persist()

    def tick(self):
        changed = self.harvest_option_lists() | self.harvest_async()
        if self.due("persist"):
            self.persist()
            changed = True
        if self.due("reload"):
            self.spawn(["hyprctl", "reload"])
        if self.due("cursor_preview"):
            self.start_cursor_preview()
        if self.due("cursor_sync"):
            self.start_cursor_sync()
        if self.watched_changed():
            self.read_state_files()
            changed = True
        return changed

    def adjust(self, row, direction):
        if row["type"] == "bool":
            self.toggle_row(row)
            return
        if row["type"] in ("enum", "pipeline"):
            self.cycle(row, direction)
            return

        step = row.get("step") or 1
        try:
            value = float(self.value_for(row))
        except (TypeError, ValueError):
            value = row["min"]
        value = min(row["max"], max(row["min"], value + step * direction))
        value = round_to(value, 3)

        if row.get("id") == "animation_speed":
            self.speed_multiplier = value
            self.apply_preview()
        else:
            self.set_override(row, value)

    def toggle_row(self, row):
        self.set_override(row, self.value_for(row) is not True)

    def cycle(self, row, direction):
        if row.get("list"):
            options = self.pipeline_options.get(row["id"], [])
        else:
            options = row.get("options") or []
        if not options:
            return
        current = str(self.value_for(row))
        index = options.index(current) if current in options else 0
        nxt = options[(index + direction) % len(options)]
        if row["type"] == "pipeline":
            self.set_pipeline(row, nxt)
        else:
            self.set_override(row, nxt)

    def move_row(self, delta):
        count = len(self.active_rows)
        if count:
            self.row_index = (self.row_index + delta) % count

    def move_section(self, delta):
        count = len(self.sections)
        self.section_index = (self.section_index + delta) % count
        self.row_index = 0
        self.row_offset = 0


PAIR_ACCENT = 1
PAIR_DIM = 2
PAIR_ERROR = 3
PAIR_BAR = 4

SECTION_WIDTH = 18
# Right-aligned in a fixed field so the gauge keeps one width per section:
# a value crossing 9 to 10 must not shorten the bar it sits beside.
VALUE_WIDTH = 5
# Blank line between option rows. The section list stays at one line per entry:
# it has no scrolling, and at this pitch twelve sections would clip off the
# bottom of a 24-line terminal.
ROW_PITCH = 2


def init_colors():
    curses.start_color()
    curses.use_default_colors()
    accent = curses.COLOR_BLUE
    dim = 8 if curses.COLORS >= 16 else curses.COLOR_WHITE
    curses.init_pair(PAIR_ACCENT, accent, -1)
    curses.init_pair(PAIR_DIM, dim, -1)
    curses.init_pair(PAIR_ERROR, curses.COLOR_RED, -1)
    curses.init_pair(PAIR_BAR, curses.COLOR_CYAN, -1)


def value_text(row, value):
    if value is None:
        return "—"
    if row["type"] == "float":
        return "%.*f" % (3 if (row.get("step") or 1) < 0.01 else 2, float(value))
    if row["type"] == "bool":
        return "on" if value is True else "off"
    return str(value)


def gauge(row, value, width):
    """A slider still reads as a slider in a terminal; the fill is the fraction
    of the row's own min..max range."""
    try:
        fraction = (float(value) - row["min"]) / (row["max"] - row["min"])
    except (TypeError, ValueError, ZeroDivisionError):
        fraction = 0.0
    fraction = min(1.0, max(0.0, fraction))
    filled = int(round(fraction * width))
    return "█" * filled + "░" * (width - filled)


def add(win, y, x, text, attr=0, limit=None):
    height, width = win.getmaxyx()
    if y < 0 or y >= height or x >= width:
        return
    room = width - x - 1
    if limit is not None:
        room = min(room, limit)
    if room <= 0:
        return
    try:
        win.addstr(y, x, text[:room], attr)
    except curses.error:
        pass


def draw(win, app):
    win.erase()
    height, width = win.getmaxyx()
    if height < 6 or width < 40:
        add(win, 0, 0, "terminal too small")
        win.noutrefresh()
        return

    accent = curses.color_pair(PAIR_ACCENT)
    dim = curses.color_pair(PAIR_DIM)

    add(win, 0, 1, "Look & Feel", accent | curses.A_BOLD)
    status = app.theme_key
    add(win, 0, max(14, width - len(status) - 2), status, dim)
    add(win, 1, 1, "─" * (width - 2), dim)

    top = 2
    bottom = height - 2
    rows_x = SECTION_WIDTH + 2

    sections = app.sections
    for index, section in enumerate(sections):
        y = top + index
        if y >= bottom:
            break
        selected = index == app.section_index
        attr = (accent | curses.A_BOLD) if selected else dim
        marker = "▌" if selected else " "
        add(win, y, 1, marker + " " + section["title"], attr, limit=SECTION_WIDTH)

    for y in range(top, bottom):
        add(win, y, SECTION_WIDTH + 1, "│", dim)

    rows = app.active_rows
    visible = max(1, (bottom - top + ROW_PITCH - 1) // ROW_PITCH)
    if app.row_index < app.row_offset:
        app.row_offset = app.row_index
    elif app.row_index >= app.row_offset + visible:
        app.row_offset = app.row_index - visible + 1

    label_width = max(12, int((width - rows_x) * 0.42))
    for slot in range(visible):
        index = app.row_offset + slot
        if index >= len(rows):
            break
        row = rows[index]
        y = top + slot * ROW_PITCH
        selected = index == app.row_index
        value = app.value_for(row)

        if app.is_overridden(row):
            add(win, y, rows_x - 1, "▌", curses.color_pair(PAIR_BAR))
        label_attr = (accent | curses.A_BOLD) if selected else 0
        add(win, y, rows_x + 1, row["label"], label_attr, limit=label_width)

        control_x = rows_x + 1 + label_width
        room = width - control_x - 2
        if room <= 4:
            continue
        text = value_text(row, value)
        if row["type"] in ("int", "float"):
            bar_width = max(4, room - VALUE_WIDTH - 1)
            add(win, y, control_x, gauge(row, value, bar_width),
                accent if selected else dim)
            add(win, y, control_x + bar_width + 1, text.rjust(VALUE_WIDTH),
                0 if selected else dim)
        elif row["type"] == "bool":
            add(win, y, control_x, "[x]" if value is True else "[ ]",
                accent if selected else 0)
        else:
            pending = (row["type"] == "pipeline"
                       and row["id"] == app.pipeline_pending_id)
            shown = "‹ %s ›" % text if selected else "  %s" % text
            add(win, y, control_x, shown + (" …" if pending else ""),
                accent if selected else 0, limit=room)

    footer = height - 1
    if app.error_text:
        add(win, footer, 1, app.error_text.replace("\n", " "),
            curses.color_pair(PAIR_ERROR))
    else:
        add(win, footer, 1, HINT, dim)
    win.noutrefresh()


def main(win):
    curses.curs_set(0)
    init_colors()
    win.keypad(True)
    win.timeout(int(WATCH_INTERVAL * 1000))

    app = Looknfeel()
    app.refresh()

    while True:
        draw(win, app)
        curses.doupdate()
        key = win.getch()

        if key == -1:
            app.tick()
            continue

        rows = app.active_rows
        row = rows[app.row_index] if 0 <= app.row_index < len(rows) else None

        # Not ESC: ncurses cannot tell a bare Escape from the first byte of an
        # escape sequence, so it holds it for ESCDELAY (1s by default) and
        # closing looked like a hang.
        if key == ord("q"):
            break
        elif key in (curses.KEY_UP, ord("k")):
            app.move_row(-1)
        elif key in (curses.KEY_DOWN, ord("j")):
            app.move_row(1)
        elif key in (curses.KEY_LEFT, ord("h")):
            if row:
                app.adjust(row, -1)
        elif key in (curses.KEY_RIGHT, ord("l")):
            if row:
                app.adjust(row, 1)
        elif key == ord("\t"):
            app.move_section(1)
        elif key == curses.KEY_BTAB:
            app.move_section(-1)
        elif key in (ord(" "), curses.KEY_ENTER, 10, 13):
            if row and row["type"] == "bool":
                app.toggle_row(row)
            elif row:
                app.adjust(row, 1)
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            if row:
                app.reset_row(row)
        elif key == curses.KEY_RESIZE:
            pass

        app.tick()

    # The preview is already live, so a pending edit has to reach the file
    # rather than evaporating at the next reload.
    app.flush()


if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        pass
