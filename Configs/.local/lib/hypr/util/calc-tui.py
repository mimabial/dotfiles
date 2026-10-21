#!/usr/bin/env python3
from __future__ import annotations

import argparse
import codecs
import curses
from curses.ascii import ctrl
from functools import cache
import locale
import os
import queue
import re
import select
import shlex
import shutil
import subprocess
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from conversion.currency import CURRENCY_NAMES
from conversion.units import UNIT_CATEGORIES
from pyutils import child_process
from pyutils.xdg_base_dirs import xdg_config_home, xdg_state_home

CURRENCY_CATEGORY = "Currency"
GROUPS = {name: tuple(symbol for symbol, _ in units) for name, units in UNIT_CATEGORIES.items()}
GROUPS[CURRENCY_CATEGORY] = tuple(CURRENCY_NAMES)
CURRENCY_EDIT_KEY = ("Edit currencies", "@currencies")
CURRENCIES_FILE = Path(os.environ.get("HYPR_CONFIG_HOME") or xdg_config_home() / "hypr") / "calc-currencies"

STATE_DIR = Path(os.environ.get("HYPR_STATE_HOME") or xdg_state_home() / "hypr")
HISTORY_FILE = STATE_DIR / "calc-history"
HISTORY_LIMIT = 1000
QALC_TIME_LIMIT_MS = 400
QALC_ANSWER_TIMEOUT_SECONDS = 3.0
QALC_RATE_FETCH_TIMEOUT_SECONDS = 15
QALC_RATE_MAX_AGE_DAYS = 1
QALC_PROMPT = "> "
QALC_READ_SIZE = 4096
KEYPAD_MIN_HEIGHT = 15
SIDE_PANEL_MIN_WIDTH = 62
HEADER_ROWS = 2
INPUT_ROWS = 3
FOOTER_ROWS = 1
SIDE_PADDING = 2
ESCAPE = "\x1b"
ESCAPE_DELAY_MS = 25
DELETE = "\x7f"
TERMINAL_DEFAULT_COLOR = -1
INPUT_PROMPT = "> "
RESULT_PROMPT = "= "
KEY_LABEL_MIN_WIDTH = 3
KEY_GAP = 1
PANEL_LABEL_WIDTH = 5
CATEGORY_KEY_PREFIX = "@cat:"

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

INPUT_HINT = "enter commit · ^Y copy · ↑↓ history · tab keys · esc clear · ^C quit"
KEYPAD_HINT = "↑↓←→ pick · enter insert · tab back to input · ^C quit"
CURRENCY_HINT = "^P currencies · "
MODE_HINT = "F1-F4"


class QalcSession:
    """One long-lived `qalc -t`, so variables, ans and settings survive."""

    def __init__(self) -> None:
        self._start()

    def _start(self) -> None:
        self.proc = subprocess.Popen(
            ["qalc", "-t", "-m", str(QALC_TIME_LIMIT_MS)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._answers: queue.Queue[str | None] = queue.Queue()
        self._notes: queue.Queue[str] = queue.Queue()
        threading.Thread(target=self._read_answers, args=(self.proc.stdout, self._answers), daemon=True).start()
        self._reader(self.proc.stderr, self._notes)

    @staticmethod
    def _read_answers(stream, answers: queue.Queue[str | None]) -> None:
        decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        pending = "\n"
        startup_prompt_seen = False
        try:
            while chunk := os.read(stream.fileno(), QALC_READ_SIZE):
                *complete, pending = (pending + decoder.decode(chunk)).split("\n" + QALC_PROMPT)
                for answer in complete:
                    if startup_prompt_seen:
                        answers.put(answer)
                    startup_prompt_seen = True
        except OSError:
            pass
        answers.put(None)

    def _reader(self, stream, sink: queue.Queue[str]) -> None:
        def pump() -> None:
            for line in stream:
                sink.put(line.rstrip("\n"))

        threading.Thread(target=pump, daemon=True).start()

    def evaluate(self, expr: str, timeout: float = QALC_ANSWER_TIMEOUT_SECONDS) -> tuple[list[str], str]:
        if not expr.strip():
            return [], ""

        try:
            self.proc.stdin.write(expr + "\n")
            self.proc.stdin.flush()
        except OSError:
            return [], "qalc session ended"

        try:
            answer = self._answers.get(timeout=timeout)
        except queue.Empty:
            self.close()
            self._start()
            return [], f"qalc gave no answer within {timeout:g} s; session restarted"
        if answer is None:
            return [], "qalc session ended"

        _echoed_input, _, body = answer.partition("\n")
        note = ""
        while not self._notes.empty():
            note = self._notes.get()
        return [line.strip() for line in body.split("\n") if line != ""], note

    def refresh_rates(self, currencies: tuple[str, ...]) -> str:
        self.evaluate(f"set update exchange rates {QALC_RATE_MAX_AGE_DAYS}")
        note = ""
        for code in currencies:
            _, warning = self.evaluate(f"1 {code} to EUR", timeout=QALC_RATE_FETCH_TIMEOUT_SECONDS + QALC_ANSWER_TIMEOUT_SECONDS)
            note = warning or note
        self.evaluate("set update exchange rates 0")
        return note

    def close(self) -> None:
        try:
            self.proc.stdin.close()
            child_process.stop(self.proc)
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


def load_currencies() -> tuple[str, ...]:
    try:
        return tuple(CURRENCIES_FILE.read_text(encoding="utf-8").split())
    except OSError:
        return GROUPS[CURRENCY_CATEGORY]


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


def copy_to_clipboard(text: str) -> bool:
    if not text or not shutil.which("wl-copy"):
        return False
    try:
        # a new session keeps wl-copy's clipboard daemon alive after this
        # terminal closes, so quitting right after a copy still leaves it set
        subprocess.run(["wl-copy", "--", text], check=True, start_new_session=True)
    except (OSError, subprocess.CalledProcessError):
        return False
    return True


def key_cell(label: str) -> str:
    return f" {label.center(max(KEY_LABEL_MIN_WIDTH, len(label)))} "


def panel_label(label: str) -> str:
    return f"{label:>{PANEL_LABEL_WIDTH}}  "


def wrap(keys: list[tuple[str, str]], width: int) -> list[list[tuple[str, str]]]:
    rows: list[list[tuple[str, str]]] = [[]]
    used = 0
    for key in keys:
        span = len(key_cell(key[0])) + KEY_GAP
        if used + span > width and rows[-1]:
            rows.append([])
            used = 0
        rows[-1].append(key)
        used += span
    return [row for row in rows if row]


def conversion_keypad(width: int, category: str, currencies: tuple[str, ...]) -> list[list[tuple[str, str]]]:
    rows = wrap([(name, CATEGORY_KEY_PREFIX + name) for name in GROUPS], width)
    symbols = currencies if category == CURRENCY_CATEGORY else GROUPS[category]
    keys = [(qalc_name(symbol), " to " + qalc_name(symbol)) for symbol in symbols]
    if category == CURRENCY_CATEGORY:
        keys.append(CURRENCY_EDIT_KEY)
    return rows + wrap(keys, width)


@cache
def keypad_space(width: int) -> int:
    return max(*(len(rows) for rows in KEYPADS.values()),
               *(len(conversion_keypad(width, category, GROUPS[CURRENCY_CATEGORY])) for category in GROUPS)) + 1


def required_terminal_size(currencies: tuple[str, ...]) -> tuple[int, int]:
    tab_width = len("│".join(f" {title} " for title in MODE_TITLES.values())) + len(MODE_HINT)
    keypad_width = max(sum(len(key_cell(label)) + KEY_GAP for label, _ in row)
                       for rows in KEYPADS.values() for row in rows)
    columns = max(SIDE_PANEL_MIN_WIDTH, tab_width, keypad_width,
                  len(CURRENCY_HINT + INPUT_HINT), len(CURRENCY_HINT + KEYPAD_HINT)) + SIDE_PADDING
    result_rows = 2
    panel_rows = max(len(currencies), *(len(units) for units in UNIT_CATEGORIES.values())) + result_rows
    rows = panel_rows + HEADER_ROWS + INPUT_ROWS + FOOTER_ROWS + keypad_space(columns - SIDE_PADDING)
    return columns, max(KEYPAD_MIN_HEIGHT, rows)


class Calculator:
    def __init__(self, screen, session: QalcSession, live: bool) -> None:
        self.screen = screen
        self.session = session
        self.live = live
        self.mode = "basic"
        self.category = "Length"
        self.currencies = load_currencies()
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
            curses.init_pair(index, self.color_for(role), TERMINAL_DEFAULT_COLOR)
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
            if self.input_pending():
                continue
            if self.live and self.dirty:
                self.evaluate()

    @staticmethod
    def input_pending() -> bool:
        return bool(select.select([sys.stdin], [], [], 0)[0])

    @staticmethod
    def color_for(role: str) -> int:
        return {
            "value": curses.COLOR_CYAN,
            "unit": curses.COLOR_GREEN,
            "name": curses.COLOR_YELLOW,
            "error": curses.COLOR_RED,
            "dim": TERMINAL_DEFAULT_COLOR,
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
        tokens = self.ask(f"({self.buffer})/(1 {qalc_name(GROUPS[category][0])})")
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
        if category != self.category:
            self.set_category(category)
            if category == CURRENCY_CATEGORY:
                self.evaluate()
                return self.extras

        rows = []
        for symbol in self.currencies if category == CURRENCY_CATEGORY else GROUPS[category]:
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
        # labelled with the name qalc accepts, so every row on screen is also
        # something the user can type
        return conversion_keypad(width, self.category, self.currencies)

    def edit_currencies(self) -> None:
        try:
            CURRENCIES_FILE.parent.mkdir(parents=True, exist_ok=True)
            if not CURRENCIES_FILE.exists():
                CURRENCIES_FILE.write_text(" ".join(self.currencies) + "\n", encoding="utf-8")
            curses.def_prog_mode()
            curses.endwin()
            try:
                subprocess.run([*shlex.split(os.environ.get("EDITOR") or "nvim"), str(CURRENCIES_FILE)])
            finally:
                curses.reset_prog_mode()
                self.screen.clearok(True)
            self.currencies = load_currencies()
            self.selection = (0, 0)
            self.focus = "input"
            self.set_category(CURRENCY_CATEGORY)
            self.dirty = True
        except OSError as error:
            self.status = str(error)

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
        elif payload.startswith(CATEGORY_KEY_PREFIX):
            self.set_category(payload.removeprefix(CATEGORY_KEY_PREFIX))
            self.dirty = True
        elif payload == "@currencies":
            self.edit_currencies()
        else:
            self.insert(payload)

    def move_selection(self, dy: int, dx: int) -> None:
        rows = self.keypad(self.screen.getmaxyx()[1] - SIDE_PADDING)
        if not rows:
            return
        row = max(0, min(len(rows) - 1, self.selection[0] + dy))
        column = max(0, min(len(rows[row]) - 1, self.selection[1] + dx))
        self.selection = (row, column)

    def selected(self) -> tuple[str, str] | None:
        rows = self.keypad(self.screen.getmaxyx()[1] - SIDE_PADDING)
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

        rows = self.keypad(width - SIDE_PADDING)
        keypad_height = keypad_space(width - SIDE_PADDING) if height >= KEYPAD_MIN_HEIGHT else 0
        footer = height - FOOTER_ROWS
        panel_top = HEADER_ROWS
        input_row = max(panel_top + 1, footer - keypad_height - INPUT_ROWS + 1)
        result_row = input_row + 1
        keypad_height = max(0, footer - result_row - 1)
        panel_bottom = input_row - 2

        self.draw_tabs(width)
        if panel_bottom >= panel_top:
            self.draw_panel(panel_top, panel_bottom, width)
        self.write(input_row - 1, 0, "─" * (width - 1), self.roles["dim"])

        input_column = len(INPUT_PROMPT)
        visible = max(1, width - input_column - 1)
        start = max(0, self.cursor - visible + 1)
        self.write(input_row, 0, INPUT_PROMPT, self.roles["dim"])
        self.write(input_row, input_column, self.buffer[start:start + visible])
        self.targets.append((input_row, input_column, width, "input", start))
        if self.result:
            self.write(result_row, 0, RESULT_PROMPT, self.roles["dim"])
            self.write_tokens(result_row, len(RESULT_PROMPT), self.result, width - 1)

        if keypad_height:
            self.draw_keypad(footer - keypad_height, rows, width, keypad_height - 1)
        self.draw_footer(footer, width)

        if self.focus == "input":
            try:
                self.screen.move(input_row, input_column + self.cursor - start)
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
        self.write(0, max(x, width - len(MODE_HINT) - SIDE_PADDING), MODE_HINT, self.roles["dim"])
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
        if width < SIDE_PANEL_MIN_WIDTH or not lines:
            return 0
        label_width = len(panel_label(""))
        needed = []
        for kind, label, payload in lines:
            if kind == "head":
                needed.append(len(label))
            elif kind == "value":
                needed.append(label_width + len(plain(payload)))
            elif kind == "var":
                needed.append(label_width + len(str(payload)))
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
                end = self.write(row, x, panel_label(label), self.roles["dim"]) if label else x
                self.write_tokens(row, end, payload, width - 1)
                self.targets.append((row, x, width, "value", plain(payload)))
            elif kind == "var":
                end = self.write(row, x, panel_label(label), self.roles["name"])
                self.write(row, end, str(payload)[: width - end - 1], self.roles["value"])
                self.targets.append((row, x, width, "var", label))

    def draw_keypad(self, top: int, rows: list[list[tuple[str, str]]], width: int, visible: int) -> None:
        self.write(top, 0, "─" * (width - 1), self.roles["dim"])
        start = max(0, min(len(rows) - visible, self.selection[0] - visible + 1)) if self.focus == "keys" else 0
        if len(rows) > visible:
            self.write(top, 1, f" {start + 1}–{min(start + visible, len(rows))}/{len(rows)} ", self.roles["dim"])
        for index in range(start, min(start + visible, len(rows))):
            keys = rows[index]
            y = top + 1 + index - start
            x = 1
            for column, key in enumerate(keys):
                cell = key_cell(key[0])
                focused = self.focus == "keys" and self.selection == (index, column)
                active = key[1] == CATEGORY_KEY_PREFIX + self.category
                attr = curses.A_REVERSE if focused else (self.roles["tab"] if active else curses.A_NORMAL)
                if x + len(cell) >= width:
                    break
                self.write(y, x, cell, attr)
                self.targets.append((y, x, x + len(cell), "key", key))
                x += len(cell) + KEY_GAP

    def draw_footer(self, row: int, width: int) -> None:
        if self.status:
            self.write(row, 0, self.status, self.roles["error"])
            return
        if self.focus == "keys":
            hint = KEYPAD_HINT
        else:
            hint = INPUT_HINT
        if self.mode == "convert" and self.category == CURRENCY_CATEGORY:
            hint = CURRENCY_HINT + hint
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
                self.cursor = max(0, min(len(self.buffer), payload + x - left))
            return

    def set_category(self, category: str) -> None:
        self.category = category
        if category == CURRENCY_CATEGORY:
            self.status = "Checking exchange rates…"
            self.draw()
            self.status = self.session.refresh_rates(self.currencies)

    def set_mode(self, mode: str) -> None:
        self.mode = mode
        self.selection = (0, 0)
        self.dirty = True
        if mode == "convert" and self.category == CURRENCY_CATEGORY:
            self.set_category(self.category)

    def navigate(self, key) -> bool:
        on_keys = self.focus == "keys"
        if key == curses.KEY_MOUSE:
            self.click()
        elif key == curses.KEY_RESIZE:
            pass
        elif key in (curses.KEY_F1, curses.KEY_F2, curses.KEY_F3, curses.KEY_F4):
            self.set_mode(MODES[key - curses.KEY_F1])
        elif key in ("\t", curses.KEY_BTAB):
            self.focus = "input" if on_keys else "keys"
        elif key == ESCAPE:
            # a bare ESC also arrives when a terminal sends an escape sequence
            # this build has no mapping for, so it must not be an instant exit.
            # It no longer exits at all: ncurses holds the byte for ESCDELAY
            # (1s by default) to tell it from a sequence, which made closing
            # look like a hang. ^C quits, as the hint says.
            if on_keys:
                self.focus = "input"
            elif self.buffer:
                self.edit("", 0)
        elif key == ctrl("l"):
            self.entries.clear()
        elif key == ctrl("p") and self.mode == "convert" and self.category == CURRENCY_CATEGORY:
            self.edit_currencies()
        elif key in ("\n", "\r", curses.KEY_ENTER):
            if not on_keys:
                self.commit()
            elif selected := self.selected():
                self.press(selected)
        elif key in (curses.KEY_UP, curses.KEY_DOWN):
            step = -1 if key == curses.KEY_UP else 1
            self.move_selection(step, 0) if on_keys else self.recall(step)
        elif key in (curses.KEY_LEFT, curses.KEY_RIGHT):
            step = -1 if key == curses.KEY_LEFT else 1
            if on_keys:
                self.move_selection(0, step)
            else:
                self.cursor = min(len(self.buffer), max(0, self.cursor + step))
        else:
            return False
        return True

    def edit_line(self, key) -> bool:
        before, after = self.buffer[: self.cursor], self.buffer[self.cursor:]
        if key in (curses.KEY_HOME, ctrl("a")):
            self.cursor = 0
        elif key in (curses.KEY_END, ctrl("e")):
            self.cursor = len(self.buffer)
        elif key in (curses.KEY_BACKSPACE, DELETE, ctrl("h")):
            if self.cursor:
                self.edit(before[:-1] + after, self.cursor - 1)
        elif key == curses.KEY_DC:
            self.edit(before + after[1:], self.cursor)
        elif key == ctrl("u"):
            self.edit(after, 0)
        elif key == ctrl("k"):
            self.edit(before, self.cursor)
        elif key == ctrl("w"):
            cut = before.rstrip().rfind(" ") + 1
            self.edit(self.buffer[:cut] + after, cut)
        elif key == ctrl("y"):
            text = plain(self.result) or (plain(self.entries[-1][1]) if self.entries else "")
            self.status = "copied" if copy_to_clipboard(text) else "nothing to copy"
        else:
            return False
        return True

    def handle(self, key) -> bool:
        if key in (ctrl("c"), ctrl("d")):
            return False
        if not (self.navigate(key) or self.edit_line(key)) and isinstance(key, str) and key.isprintable():
            self.edit(self.buffer[: self.cursor] + key + self.buffer[self.cursor:], self.cursor + 1)
        return True


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="hyprshell util/calc-tui",
        description="Calculator TUI backed by a persistent qalc session",
    )
    parser.add_argument("--size", action="store_true", help="print the terminal columns and rows needed for the calculator")
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

    if args.size:
        print(*required_terminal_size(load_currencies()))
        return 0

    if not shutil.which("qalc"):
        print("qalc not found; install libqalculate", file=sys.stderr)
        return 1

    locale.setlocale(locale.LC_ALL, "")
    os.environ.setdefault("ESCDELAY", str(ESCAPE_DELAY_MS))

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
