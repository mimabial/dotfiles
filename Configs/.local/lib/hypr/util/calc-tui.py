#!/usr/bin/env python3
"""Curses calculator over a persistent qalc session."""

from __future__ import annotations

import argparse
import curses
import locale
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
# the converter popup owns the curated unit table; reuse it rather than
# maintaining a second one
from converter import GROUPS

STATE_DIR = Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr"))
HISTORY_FILE = STATE_DIR / "calc-history"
HISTORY_LIMIT = 1000
# keep any single evaluation inside the frame read budget below
TIME_LIMIT_MS = 400
POLL_MS = 5

SGR = re.compile(r"\x1b\[([0-9;]*)m")
ANS = re.compile(r"\bans\b")
ASSIGN = re.compile(r"^\s*([A-Za-z_]\w*)\s*=(?!=)")

# qalc colours numbers cyan, units green and unknown variables yellow-italic
SGR_COLOR = {"31": "error", "32": "unit", "33": "name", "36": "value"}

MODES = ("basic", "scientific", "programmer", "convert")
MODE_TITLES = {"basic": "Basic", "scientific": "Scientific",
               "programmer": "Programmer", "convert": "Convert"}

KEYPADS = {
    "basic": [
        [("7", "7"), ("8", "8"), ("9", "9"), ("/", "/"), ("(", "("), (")", ")")],
        [("4", "4"), ("5", "5"), ("6", "6"), ("*", "*"), ("^", "^"), ("%", "%")],
        [("1", "1"), ("2", "2"), ("3", "3"), ("-", "-"), (".", "."), (",", ",")],
        [("0", "0"), ("+", "+"), ("√", "sqrt("), ("ans", "ans"), ("del", "@back"), ("clr", "@clear")],
    ],
    "scientific": [
        [("sin", "sin("), ("cos", "cos("), ("tan", "tan("), ("asin", "asin("),
         ("acos", "acos("), ("atan", "atan(")],
        [("ln", "ln("), ("log", "log("), ("exp", "exp("), ("√", "sqrt("),
         ("x²", "^2"), ("x^y", "^")],
        [("π", "pi"), ("e", "e"), ("!", "!"), ("abs", "abs("),
         ("round", "round("), ("%", "%")],
        [("(", "("), (")", ")"), ("ans", "ans"), ("del", "@back"), ("clr", "@clear")],
    ],
    "programmer": [
        [("A", "A"), ("B", "B"), ("C", "C"), ("D", "D"), ("E", "E"), ("F", "F")],
        [("0x", "0x"), ("0b", "0b"), ("0o", "0o"), ("<<", " << "), (">>", " >> "),
         ("mod", " mod ")],
        [("and", " and "), ("or", " or "), ("xor", " xor "), ("not", "not "),
         ("(", "("), (")", ")")],
        [("ans", "ans"), ("del", "@back"), ("clr", "@clear")],
    ],
}

# the converter's labels are what a person expects to read, but several of them
# parse as something else entirely in qalc: st becomes second-tonne, BTU becomes
# b-t-u, and a bare cup/tbsp/tsp is the metric one rather than the US measure
# the table means
QALC_NAMES = {
    "st": "stone", "kn": "knot", "KB": "kilobyte", "BTU": "Btu",
    "pt": "liq_pt", "qt": "liq_qt", "cup": "cup_US",
    "tbsp": "tbsp_US", "tsp": "tsp_US",
}

EXTRAS = {
    "scientific": [("frac", "fraction"), ("sci", "sci")],
    "programmer": [("hex", "hex"), ("oct", "octal"), ("bin", "binary")],
}


class QalcSession:
    """One long-lived `qalc -t`, so variables, ans and settings survive."""

    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            ["qalc", "-t", "-m", str(TIME_LIMIT_MS)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._lines: queue.Queue[str] = queue.Queue()
        self._notes: queue.Queue[str] = queue.Queue()
        self._reader(self.proc.stdout, self._lines)
        self._reader(self.proc.stderr, self._notes)

    def _reader(self, stream, sink: queue.Queue[str]) -> None:
        def pump() -> None:
            for line in stream:
                sink.put(line.rstrip("\n"))

        threading.Thread(target=pump, daemon=True).start()

    def evaluate(self, expr: str, budget: float = 3.0) -> tuple[list[str], str]:
        """Return the result lines and any note qalc wrote to stderr.

        Piped qalc answers in a fixed frame: the echoed input, a blank line, the
        result, then an empty line. Internal blank lines inside a result carry
        indentation, so only a truly empty line ends it.
        """
        if not expr.strip():
            return [], ""

        while not self._lines.empty():
            self._lines.get()

        try:
            self.proc.stdin.write(expr + "\n")
            self.proc.stdin.flush()
        except OSError:
            return [], "qalc session ended"

        body: list[str] = []
        echoed = False
        while True:
            try:
                line = self._lines.get(timeout=budget)
            except queue.Empty:
                break
            if not echoed:
                echoed = line.startswith("> ")
                continue
            if line == "" and body:
                break
            if line != "":
                body.append(line)
            budget = 0.5

        note = ""
        while not self._notes.empty():
            note = self._notes.get()
        return [line.strip() for line in body], note

    def close(self) -> None:
        try:
            self.proc.stdin.close()
            self.proc.terminate()
            self.proc.wait(timeout=1)
        except (OSError, subprocess.SubprocessError):
            pass


def tokenize(line: str) -> list[tuple[str, str]]:
    tokens: list[tuple[str, str]] = []
    role = "plain"
    pos = 0
    for match in SGR.finditer(line):
        if match.start() > pos:
            tokens.append((line[pos:match.start()], role))
        for code in match.group(1).split(";"):
            if code in ("", "0"):
                role = "plain"
            elif code in SGR_COLOR:
                role = SGR_COLOR[code]
        pos = match.end()
    if pos < len(line):
        tokens.append((line[pos:], role))
    return [token for token in tokens if token[0]]


def plain(tokens: list[tuple[str, str]]) -> str:
    return "".join(text for text, _ in tokens)


def unit_of(tokens: list[tuple[str, str]]) -> str:
    return next((text.strip() for text, role in tokens if role == "unit" and text.strip()), "")


def qalc_name(symbol: str) -> str:
    return QALC_NAMES.get(symbol, symbol)


def base_unit(category: str) -> str:
    return next(symbol for symbol, scale in GROUPS[category] if scale == 1)


def load_history() -> list[str]:
    try:
        lines = HISTORY_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    return [line for line in lines if line.strip()][-HISTORY_LIMIT:]


def append_history(expr: str) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with HISTORY_FILE.open("a", encoding="utf-8") as handle:
            handle.write(expr + "\n")
    except OSError:
        pass


def copy(text: str) -> bool:
    if not text or not shutil.which("wl-copy"):
        return False
    try:
        # a new session keeps wl-copy's clipboard daemon alive after this
        # terminal closes, so quitting right after a copy still leaves it set
        subprocess.run(["wl-copy", "--", text], check=True, start_new_session=True)
    except (OSError, subprocess.CalledProcessError):
        return False
    return True


def wrap(keys: list[tuple[str, str]], width: int) -> list[list[tuple[str, str]]]:
    rows: list[list[tuple[str, str]]] = [[]]
    used = 0
    for key in keys:
        span = max(3, len(key[0])) + 3
        if used + span > width and rows[-1]:
            rows.append([])
            used = 0
        rows[-1].append(key)
        used += span
    return [row for row in rows if row]


class Calculator:
    def __init__(self, screen, session: QalcSession, live: bool) -> None:
        self.screen = screen
        self.session = session
        self.live = live
        self.mode = "basic"
        self.category = "Length"
        self.buffer = ""
        self.cursor = 0
        self.result: list[tuple[str, str]] = []
        self.extras: list[tuple[str, list[tuple[str, str]]]] = []
        self.status = ""
        self.last = ""
        self.dirty = False
        self.focus = "input"
        self.selection = (0, 0)
        self.targets: list[tuple[int, int, int, str, object]] = []
        self.roles: dict[str, int] = {}
        self.entries: list[tuple[str, list[tuple[str, str]]]] = []
        self.variables: dict[str, str] = {}
        self.history = load_history()
        self.history_pos = len(self.history)

    def setup(self) -> None:
        curses.use_default_colors()
        curses.curs_set(1)
        curses.mousemask(curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED)
        names = ("value", "unit", "name", "error", "dim", "tab")
        for index, role in enumerate(names, start=1):
            curses.init_pair(index, self.color_for(role), -1)
        self.roles = {role: curses.color_pair(index) for index, role in enumerate(names, start=1)}
        self.roles["plain"] = curses.A_NORMAL
        self.roles["dim"] |= curses.A_DIM
        self.roles["tab"] |= curses.A_BOLD

    def run(self) -> None:
        self.setup()
        while True:
            self.draw()
            try:
                key = self.screen.get_wch()
            except curses.error:
                continue
            if self.handle(key) is False:
                return
            if not self.drain():
                return
            if self.live and self.dirty:
                self.evaluate()

    def drain(self) -> bool:
        """Absorb a burst of keys, so a paste costs one evaluation.

        A pasted line arrives in chunks with sub-millisecond gaps; evaluating
        every prefix of a long expression costs the better part of a second.

        This waits rather than polling: under nodelay ncurses cannot assemble an
        escape sequence, so an arrow key caught mid-burst arrives as a bare ESC
        followed by its bytes as literal text.
        """
        self.screen.timeout(POLL_MS)
        grace = True
        try:
            while True:
                try:
                    key = self.screen.get_wch()
                except curses.error:
                    if not grace:
                        return True
                    grace = False
                    continue
                grace = True
                if self.handle(key) is False:
                    return False
        finally:
            self.screen.timeout(-1)

    @staticmethod
    def color_for(role: str) -> int:
        return {
            "value": curses.COLOR_CYAN,
            "unit": curses.COLOR_GREEN,
            "name": curses.COLOR_YELLOW,
            "error": curses.COLOR_RED,
            "dim": -1,
            "tab": curses.COLOR_CYAN,
        }[role]

    def ask(self, expr: str) -> list[tuple[str, str]]:
        lines, _ = self.session.evaluate(ANS.sub(f"({self.last or '0'})", expr))
        return tokenize(" ".join(lines)) if lines else []

    def evaluate(self) -> None:
        self.dirty = False
        self.extras = []
        if not self.buffer.strip():
            self.result = []
            self.status = ""
            return
        # each keystroke re-evaluates, and a half-typed `a`/`an` is a valid
        # symbolic expression that overwrites qalc's own ans, so `ans` is
        # resolved here against the last committed result instead
        lines, note = self.session.evaluate(ANS.sub(f"({self.last or '0'})", self.buffer))
        self.result = tokenize(" ".join(lines)) if lines else []
        self.status = note
        if self.result:
            self.extras = self.mode_extras()

    def mode_extras(self) -> list[tuple[str, list[tuple[str, str]]]]:
        if self.mode == "convert":
            return self.conversions()
        rows = []
        for label, target in EXTRAS.get(self.mode, []):
            tokens = self.ask(f"({self.buffer}) to {target}")
            if tokens and plain(tokens) != plain(self.result):
                rows.append((label, tokens))
        return rows

    def fits(self, category: str) -> bool:
        tokens = self.ask(f"({self.buffer})/(1 {qalc_name(base_unit(category))})")
        return bool(tokens) and not unit_of(tokens)

    def conversions(self) -> list[tuple[str, list[tuple[str, str]]]]:
        if not unit_of(self.result):
            return []
        # qalc normalises freely - 1 gal comes back as mm³ - so the category is
        # found by asking what the value actually divides into cleanly, not by
        # matching the unit it happened to print
        category = self.category if self.fits(self.category) else ""
        if not category:
            category = next((name for name in GROUPS if self.fits(name)), "")
        if not category:
            return []
        self.category = category

        rows = []
        for symbol, _ in GROUPS[category]:
            name = qalc_name(symbol)
            tokens = self.ask(f"({self.buffer})/(1 {name})")
            if tokens and not unit_of(tokens):
                rows.append((name, tokens + [(" " + name, "unit")]))
        return rows

    def commit(self) -> None:
        expr = self.buffer.strip()
        if not expr:
            return
        if self.dirty:
            self.evaluate()
        if not self.result:
            return
        # the live preview already advanced qalc's `ans`, so the last preview is
        # the committed result; re-sending would apply the expression twice
        self.entries.append((expr, self.result))
        self.last = plain(self.result)
        assigned = ASSIGN.match(expr)
        if assigned:
            self.variables[assigned.group(1)] = plain(self.result)
        if not self.history or self.history[-1] != expr:
            self.history.append(expr)
            append_history(expr)
        self.history_pos = len(self.history)
        self.buffer = ""
        self.cursor = 0
        self.result = []
        self.extras = []
        self.status = ""

    def keypad(self, width: int) -> list[list[tuple[str, str]]]:
        if self.mode != "convert":
            return KEYPADS[self.mode]
        rows = wrap([(name, "@cat:" + name) for name in GROUPS], width)
        # labelled with the name qalc accepts, so every row on screen is also
        # something the user can type
        rows += wrap([(qalc_name(symbol), " to " + qalc_name(symbol))
                      for symbol, _ in GROUPS[self.category]], width)
        return rows

    def insert(self, text: str) -> None:
        self.edit(self.buffer[: self.cursor] + text + self.buffer[self.cursor:],
                  self.cursor + len(text))

    def press(self, key: tuple[str, str]) -> None:
        _, payload = key
        if payload == "@clear":
            self.edit("", 0)
        elif payload == "@back":
            if self.cursor:
                self.edit(self.buffer[: self.cursor - 1] + self.buffer[self.cursor:], self.cursor - 1)
        elif payload.startswith("@cat:"):
            self.category = payload[5:]
            self.dirty = True
        else:
            self.insert(payload)

    def move_selection(self, dy: int, dx: int) -> None:
        rows = self.keypad(self.screen.getmaxyx()[1] - 2)
        if not rows:
            return
        row = max(0, min(len(rows) - 1, self.selection[0] + dy))
        column = max(0, min(len(rows[row]) - 1, self.selection[1] + dx))
        self.selection = (row, column)

    def selected(self) -> tuple[str, str] | None:
        rows = self.keypad(self.screen.getmaxyx()[1] - 2)
        row, column = self.selection
        if row < len(rows) and column < len(rows[row]):
            return rows[row][column]
        return None

    def write(self, y: int, x: int, text: str, attr: int = curses.A_NORMAL) -> int:
        height, width = self.screen.getmaxyx()
        if y < 0 or y >= height or x >= width:
            return x
        text = text[: max(0, width - x - 1)]
        try:
            self.screen.addstr(y, x, text, attr)
        except curses.error:
            pass
        return x + len(text)

    def write_tokens(self, y: int, x: int, tokens: list[tuple[str, str]], limit: int) -> None:
        for text, role in tokens:
            if x >= limit:
                return
            x = self.write(y, x, text[: limit - x], self.roles.get(role, curses.A_NORMAL))

    def draw(self) -> None:
        self.screen.erase()
        height, width = self.screen.getmaxyx()
        self.targets = []

        rows = self.keypad(width - 2)
        keypad_height = len(rows) + 1 if height >= 15 else 0
        footer = height - 1
        result_row = footer - keypad_height - 1
        input_row = result_row - 1
        panel_top, panel_bottom = 2, input_row - 2

        self.draw_tabs(width)
        if panel_bottom >= panel_top:
            self.draw_panel(panel_top, panel_bottom, width)
        self.write(input_row - 1, 0, "─" * (width - 1), self.roles["dim"])

        visible = max(1, width - 3)
        start = max(0, self.cursor - visible + 1)
        self.write(input_row, 0, "> ", self.roles["dim"])
        self.write(input_row, 2, self.buffer[start:start + visible])
        self.targets.append((input_row, 2, width, "input", start))
        if self.result:
            self.write(result_row, 0, "= ", self.roles["dim"])
            self.write_tokens(result_row, 2, self.result, width - 1)

        if keypad_height:
            self.draw_keypad(footer - keypad_height, rows, width)
        self.draw_footer(footer, width)

        if self.focus == "input":
            try:
                self.screen.move(input_row, 2 + self.cursor - start)
            except curses.error:
                pass
        self.screen.refresh()

    def draw_tabs(self, width: int) -> None:
        x = 1
        for index, mode in enumerate(MODES):
            if index:
                x = self.write(0, x, "│", self.roles["dim"])
            label = f" {MODE_TITLES[mode]} "
            active = mode == self.mode
            self.write(0, x, label, self.roles["tab"] | curses.A_REVERSE if active else self.roles["dim"])
            self.targets.append((0, x, x + len(label), "tab", mode))
            x += len(label)
        self.write(0, max(x, width - 7), "F1-F4", self.roles["dim"])
        self.write(1, 0, "─" * (width - 1), self.roles["dim"])

    def panel_lines(self) -> list[tuple[str, str, object]]:
        """The side column as rows, so it can be sized to its own content."""
        lines: list[tuple[str, str, object]] = []
        if self.result:
            lines.append(("head", "result", None))
            lines.append(("value", "", self.result))
            lines += [("value", label, tokens) for label, tokens in self.extras]
        if self.variables or self.last:
            if lines:
                lines.append(("gap", "", None))
            lines.append(("head", "vars", None))
            lines += [("var", name, value) for name, value in self.variables.items()]
            if self.last:
                lines.append(("var", "ans", self.last))
        return lines

    def panel_width(self, lines: list[tuple[str, str, object]], width: int) -> int:
        if width < 62 or not lines:
            return 0
        needed = []
        for kind, label, payload in lines:
            if kind == "head":
                needed.append(len(label))
            elif kind == "value":
                needed.append(7 + len(plain(payload)))
            elif kind == "var":
                needed.append(7 + len(str(payload)))
        return min(max(needed) + 2, width // 3)

    def draw_panel(self, top: int, bottom: int, width: int) -> None:
        lines = self.panel_lines()[: max(0, bottom - top + 1)]
        side = self.panel_width(lines, width)
        divider = width - side - 2
        last = top + len(lines) - 1 if side else top - 1

        for offset, (expr, tokens) in enumerate(reversed(self.entries)):
            row = bottom - offset
            if row < top:
                break
            limit = divider - 1 if side and row <= last else width - 1
            # the result is the point of the row, so a long expression is what
            # gives way when the two do not fit together
            room = limit - len(" = ") - len(plain(tokens))
            shown = expr if len(expr) <= room else expr[: max(0, room - 1)] + "…"
            end = self.write(row, 0, shown, self.roles["dim"])
            end = self.write(row, end, " = ", self.roles["dim"])
            self.write_tokens(row, end, tokens, limit)
            self.targets.append((row, 0, limit, "tape", expr))

        if not side:
            return
        x = divider + 2
        for offset, (kind, label, payload) in enumerate(lines):
            row = top + offset
            self.write(row, divider, "│", self.roles["dim"])
            if kind == "head":
                self.write(row, x, label, self.roles["dim"])
            elif kind == "value":
                end = self.write(row, x, f"{label:>5}  ", self.roles["dim"]) if label else x
                self.write_tokens(row, end, payload, width - 1)
                self.targets.append((row, x, width, "value", plain(payload)))
            elif kind == "var":
                end = self.write(row, x, f"{label:>5}  ", self.roles["name"])
                self.write(row, end, str(payload)[: width - end - 1], self.roles["value"])
                self.targets.append((row, x, width, "var", label))

    def draw_keypad(self, top: int, rows: list[list[tuple[str, str]]], width: int) -> None:
        self.write(top, 0, "─" * (width - 1), self.roles["dim"])
        for index, keys in enumerate(rows):
            y = top + 1 + index
            x = 1
            for column, key in enumerate(keys):
                label = key[0].center(max(3, len(key[0])))
                cell = f" {label} "
                focused = self.focus == "keys" and self.selection == (index, column)
                active = key[1] == "@cat:" + self.category
                attr = curses.A_REVERSE if focused else (self.roles["tab"] if active else curses.A_NORMAL)
                if x + len(cell) >= width:
                    break
                self.write(y, x, cell, attr)
                self.targets.append((y, x, x + len(cell), "key", key))
                x += len(cell) + 1

    def draw_footer(self, row: int, width: int) -> None:
        if self.status:
            self.write(row, 0, self.status, self.roles["error"])
            return
        if self.focus == "keys":
            hint = "↑↓←→ pick · enter insert · tab back to input · ^C quit"
        else:
            hint = "enter commit · ^Y copy · ↑↓ history · tab keys · esc clear · ^C quit"
        self.write(row, 0, hint, self.roles["dim"])

    def recall(self, delta: int) -> None:
        if not self.history:
            return
        self.history_pos = max(0, min(len(self.history), self.history_pos + delta))
        self.buffer = "" if self.history_pos == len(self.history) else self.history[self.history_pos]
        self.cursor = len(self.buffer)
        self.dirty = True
        if not self.live:
            self.result = []

    def edit(self, buffer: str, cursor: int) -> None:
        self.buffer = buffer
        self.cursor = cursor
        self.history_pos = len(self.history)
        self.dirty = True
        if not self.live:
            self.result = []

    def click(self) -> None:
        try:
            _, x, y, _, _ = curses.getmouse()
        except curses.error:
            return
        for row, left, right, kind, payload in self.targets:
            if row != y or not left <= x < right:
                continue
            if kind == "key":
                self.press(payload)
            elif kind == "tab":
                self.set_mode(payload)
            elif kind == "tape":
                self.focus = "input"
                self.edit(payload, len(payload))
            elif kind in ("value", "var"):
                self.focus = "input"
                self.insert(payload)
            elif kind == "input":
                self.focus = "input"
                self.cursor = max(0, min(len(self.buffer), payload + x - 2))
            return

    def set_mode(self, mode: str) -> None:
        self.mode = mode
        self.selection = (0, 0)
        self.dirty = True

    def handle(self, key) -> bool:
        if key == curses.KEY_MOUSE:
            self.click()
            return True
        if key == curses.KEY_RESIZE:
            return True
        if key in ("\x03", "\x04") or key in (3, 4):
            return False
        if key in (curses.KEY_F1, curses.KEY_F2, curses.KEY_F3, curses.KEY_F4):
            self.set_mode(MODES[key - curses.KEY_F1])
            return True
        if key in ("\t", 9, curses.KEY_BTAB):
            self.focus = "keys" if self.focus == "input" else "input"
            return True
        if key in ("\x1b", 27):
            # a bare ESC also arrives when a terminal sends an escape sequence
            # this build has no mapping for, so it must not be an instant exit.
            # It no longer exits at all: ncurses holds the byte for ESCDELAY
            # (1s by default) to tell it from a sequence, which made closing
            # look like a hang. ^C quits, as the hint says.
            if self.focus == "keys":
                self.focus = "input"
            elif self.buffer:
                self.edit("", 0)
            return True
        if key in ("\x0c", 12):
            self.entries.clear()
            return True
        if key in ("\n", "\r", curses.KEY_ENTER) or key == 10:
            if self.focus == "keys":
                selected = self.selected()
                if selected:
                    self.press(selected)
            else:
                self.commit()
            return True
        if key in (curses.KEY_UP, 259):
            self.move_selection(-1, 0) if self.focus == "keys" else self.recall(-1)
            return True
        if key in (curses.KEY_DOWN, 258):
            self.move_selection(1, 0) if self.focus == "keys" else self.recall(1)
            return True
        if key in (curses.KEY_LEFT, 260):
            if self.focus == "keys":
                self.move_selection(0, -1)
            else:
                self.cursor = max(0, self.cursor - 1)
            return True
        if key in (curses.KEY_RIGHT, 261):
            if self.focus == "keys":
                self.move_selection(0, 1)
            else:
                self.cursor = min(len(self.buffer), self.cursor + 1)
            return True
        if key in (curses.KEY_HOME, 262, "\x01"):
            self.cursor = 0
            return True
        if key in (curses.KEY_END, 360, "\x05"):
            self.cursor = len(self.buffer)
            return True
        if key in (curses.KEY_BACKSPACE, 263, "\x7f", "\x08"):
            if self.cursor:
                self.edit(self.buffer[: self.cursor - 1] + self.buffer[self.cursor:], self.cursor - 1)
            return True
        if key in (curses.KEY_DC, 330):
            self.edit(self.buffer[: self.cursor] + self.buffer[self.cursor + 1:], self.cursor)
            return True
        if key == "\x15":
            self.edit(self.buffer[self.cursor:], 0)
            return True
        if key == "\x0b":
            self.edit(self.buffer[: self.cursor], self.cursor)
            return True
        if key == "\x17":
            head = self.buffer[: self.cursor].rstrip()
            cut = head.rfind(" ") + 1
            self.edit(self.buffer[:cut] + self.buffer[self.cursor:], cut)
            return True
        if key == "\x19":
            text = plain(self.result) or (plain(self.entries[-1][1]) if self.entries else "")
            self.status = "copied" if copy(text) else "nothing to copy"
            return True
        if isinstance(key, str) and key.isprintable():
            self.edit(self.buffer[: self.cursor] + key + self.buffer[self.cursor:], self.cursor + 1)
        return True


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="hyprshell util/calc-tui",
        description="Calculator TUI backed by a persistent qalc session",
    )
    parser.add_argument(
        "--mode",
        choices=MODES,
        default="basic",
        help="tab to open on (default: basic)",
    )
    parser.add_argument(
        "--no-live",
        dest="live",
        action="store_false",
        help="evaluate only on enter instead of on every keystroke",
    )
    args = parser.parse_args()

    if not shutil.which("qalc"):
        print("qalc not found; install libqalculate", file=sys.stderr)
        return 1

    locale.setlocale(locale.LC_ALL, "")
    os.environ.setdefault("ESCDELAY", "25")

    session = QalcSession()
    session.evaluate("0")

    def start(screen) -> None:
        calculator = Calculator(screen, session, args.live)
        calculator.set_mode(args.mode)
        calculator.run()

    try:
        curses.wrapper(start)
    except KeyboardInterrupt:
        pass
    finally:
        session.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
