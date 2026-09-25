"""hyprmoncfg terminal editor, laid out after upstream hyprmoncfg's TUI.

The draft is edited in-process with the daemon's own edit functions; anything that
touches the live setup goes through hyprmoncfgd as a preview that reverts unless kept.
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Callable

from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.events import DescendantFocus, MouseDown, MouseMove, MouseUp, Resize
from textual.geometry import Region
from textual.screen import ModalScreen
from textual.widget import Widget
from textual.widgets import ContentSwitcher, Input, OptionList, Static
from textual.widgets.option_list import Option

from . import VERSION, daemon, hypr, profiles, workspaces
from .cli import frame, request

VARIANT_FILE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "hypr/color_variant"
LIGHT = VARIANT_FILE.is_file() and VARIANT_FILE.read_text().strip() == "light"
GRAY = (
    {"grid": "#d4d4d4", "frame": "#b4b4b4", "label": "#8a8a8a"}
    if LIGHT
    else {"grid": "#3b3b3b", "frame": "#5b5b5b", "label": "#6b6b6b"}
)
PREVIEW_SECONDS = 10
CELL_ASPECT = 2
GRID_STEP = (8, 4)
TABS = {"layout": "Layout", "profiles": "Profiles", "workspaces": "Workspaces"}
PAGES = {
    "display": ("enabled", "mode", "scale", "vrr", "transform", "x", "y", "mirror_of"),
    "color": ("bitdepth", "cm", "sdr_brightness", "sdr_saturation"),
}
ROTATIONS = ("normal", "90°", "180°", "270°", "flipped", "flipped 90°", "flipped 180°", "flipped 270°")
COLOR_MODES = ("srgb", "auto", "wide", "hdr", "hdredid", "dcip3", "dp3", "adobe", "edid")
STRATEGIES = ("sequential", "interleave", "manual")
VRR_MODES = ("off", "on", "fullscreen")
MOVE_STEPS = {"": 100, "shift+": 10, "ctrl+": 1}
ARROWS = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}
SNAP_KEYS = {"h": "left", "j": "down", "k": "up", "l": "right"}
REASONS = {
    "connected": "connected",
    "connected_kept_off": "connected, kept off",
    "not_connected": "missing",
    "not_connected_kept_off": "missing, kept off",
    "connected_unknown": "connected but not in the profile",
}
HINTS = {
    "canvas": "drag/arrows move|[ ] monitors|hjkl snap|Tab pane|a apply|s save|? keys",
    "inspector": "↑↓ select|←→ adjust|Enter edit|Tab pane|a apply|s save|? keys",
    "profile-list": "↑↓ browse|Enter apply|Space auto|l edit|e exec|d delete|? keys",
    "workspace-list": "↑↓ select|←→ adjust|a apply|s save|? keys",
}
HELP = {
    "Layout": [
        ("drag, arrows", "move the selected display by 100px"),
        ("shift/ctrl+arrows", "move it by 10px or 1px"),
        ("h j k l", "snap it beside the nearest display"),
        ("0", "move it to 0,0"),
        ("[ ]", "select the previous or next display"),
        ("Tab", "move between canvas, Display and Color"),
        ("↑↓ ←→ Enter", "pick a field, adjust it, type X or Y"),
    ],
    "Profiles": [
        ("Enter, a", "apply the selected profile"),
        ("l  e  d", "load into the editor, edit exec, delete"),
        ("Space", "toggle automatic profile selection"),
    ],
    "Workspaces": [("↑↓ ←→", "pick a setting, adjust it or reorder displays")],
    "Anywhere": [
        ("1 2 3", "switch tabs"),
        ("a  s  r", "apply, save, or reset from live state"),
        ("y  n", "keep or revert a running preview"),
        ("q", "quit"),
    ],
}
OUTPUT_DEFAULTS = {
    "enabled": True, "mode": "", "scale": 1, "transform": 0, "x": 0, "y": 0, "mirror_of": "",
    "bitdepth": 8, "cm": "srgb", "sdr_brightness": 1, "sdr_saturation": 1,
}


def cycle(options, current, delta: int):
    options = list(options)
    if not options:
        return current
    return options[((options.index(current) if current in options else 0) + delta) % len(options)]


def sdr_step(value: float, delta: int) -> float:
    return round(min(3, max(0, value + delta / 20)), 2)


def model_of(output: dict) -> str:
    made = f"{output.get('make', '')} {output.get('model', '')}".strip()
    return made or output.get("description") or output.get("name", "")


def table(pairs, width: int) -> Text:
    rows = (Text.assemble((f"{label:<{width}}", GRAY["label"]), value) for label, value in pairs)
    return Text("\n").join(rows)


def option(label: str, value, option_id: str) -> Option:
    return Option(Text.assemble((f"{label:<15}", GRAY["label"]), str(value)), id=option_id)


def hint_line(spec: str) -> Text:
    items = (item.rpartition(" ") for item in spec.split("|"))
    return Text(" | ").join(Text.assemble((keys, "green"), f" {action}") for keys, _, action in items)


def grid(width: int, height: int) -> str:
    def cell(x: int, y: int) -> str:
        on_row, on_column = y % GRID_STEP[1] == 0, x % GRID_STEP[0] == 0
        return "┼" if on_row and on_column else "─" if on_row else "│" if on_column else " "

    return "\n".join("".join(cell(x, y) for x in range(width)) for y in range(height))


def planned(profile: dict) -> dict:
    """The profile with its planner on, to show what the rules would be."""
    return {**profile, "workspaces": {**profile.get("workspaces", {}), "enabled": True}}


def plan_lines(profile: dict) -> list[str]:
    outputs = {o["key"]: o for o in profile.get("outputs", [])}
    rows = [(model_of(outputs.get(r["output_key"], {})), r["workspaces"]) for r in workspaces.plan(profile)]
    width = max((len(model) for model, _ in rows), default=0) + 2
    return [f"{model:<{width}}{', '.join(numbers)}" for model, numbers in rows]


def profile_row(summary: dict) -> Text:
    flag, score = "active" if summary["active"] else "", f"{summary['match_score']:>6}"
    return Text.assemble(f"  {summary['name']:<34}", (f"{flag:>6}", "bold green"), score)


def reason_line(reason: dict) -> Text:
    count = reason["count"]
    what = f"{count} display{'' if count == 1 else 's'} {REASONS[reason['kind']]}"
    return Text.assemble((f" {reason['points']:+d} ", GRAY["label"]), what)


def mode_card(output: dict) -> Text:
    output = OUTPUT_DEFAULTS | output
    width, height = daemon.logical_size(output)
    kind = "Internal · " if hypr.is_internal(output) else ""
    details = [f"{kind}{model_of(output)}", output["mode"], f"{output['scale']:g}x={width}x{height}"]
    details.append(f"pos {output['x']},{output['y']}")
    return Text.assemble((output.get("name", ""), "bold"), "\n", ("\n".join(details), GRAY["label"]))


def fill(options: OptionList, rows: list[Option]) -> None:
    highlighted = options.highlighted or 0
    options.set_options(rows)
    enabled = [index for index, row in enumerate(rows) if not row.disabled]
    if enabled:
        options.highlighted = min(enabled, key=lambda index: abs(index - highlighted))


class Prompt(ModalScreen):
    AUTO_FOCUS = "Input"
    BINDINGS = [Binding("escape", "dismiss")]

    def __init__(self, heading: str, label: str, value: str, kind: str) -> None:
        super().__init__()
        self.heading, self.label, self.field = heading, label, Input(value, type=kind)

    def compose(self) -> ComposeResult:
        with Vertical(classes="dialog"):
            yield Static(Text.assemble((self.heading, "bold"), "\n\n", (self.label, GRAY["label"])))
            yield self.field
            yield Static(Text("Enter confirms. Esc cancels.", GRAY["label"]))

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if not event.validation_result or event.validation_result.is_valid:
            self.dismiss(event.value.strip())


class Help(ModalScreen):
    BINDINGS = [Binding("escape,question_mark,q,enter", "dismiss")]

    def compose(self) -> ComposeResult:
        yield Static(Text("\n\n").join(
            Text.assemble((group, "bold"), "\n", table([(keys, action) for keys, action in rows], 20))
            for group, rows in HELP.items()
        ), classes="dialog")


class Card(Static):
    """One display on a canvas; on the editable one, dragging moves it by the cells travelled."""

    def __init__(self, body: Text, key: str, cell: float, region: Region, selected: bool) -> None:
        super().__init__(body, classes="selected" if selected else "")
        self.key, self.cell, self.origin, self.grab = key, cell, region.offset, None
        self.styles.offset = region.offset
        self.styles.width, self.styles.height = region.size

    def on_mouse_down(self, event: MouseDown) -> None:
        if self.parent.can_focus:
            self.grab = event.screen_offset
            self.capture_mouse()

    def on_mouse_move(self, event: MouseMove) -> None:
        if self.grab is not None:
            self.styles.offset = self.origin + event.screen_offset - self.grab

    def on_mouse_up(self, event: MouseUp) -> None:
        if self.grab is not None:
            self.release_mouse()
            moved, self.grab = event.screen_offset - self.grab, None
            row_height = self.cell * CELL_ASPECT
            self.app.drop(self.key, moved.x * self.cell, moved.y * row_height, row_height)


class Canvas(Widget, can_focus=True):
    BINDINGS = [
        *(
            Binding(f"{modifier}{arrow}", f"app.nudge({dx * step}, {dy * step})")
            for modifier, step in MOVE_STEPS.items()
            for arrow, (dx, dy) in ARROWS.items()
        ),
        *(Binding(key, f"app.snap('{direction}')") for key, direction in SNAP_KEYS.items()),
        Binding("0", "app.origin"),
        Binding("left_square_bracket", "app.select_output(-1)"),
        Binding("right_square_bracket", "app.select_output(1)"),
    ]

    def __init__(self, body: Callable[[dict], Text], editable: bool = False, **kwargs) -> None:
        super().__init__(classes="panel", **kwargs)
        self.body, self.can_focus, self.profile, self.selected = body, editable, {}, ""
        self.border_title = "Monitor Layout"

    def show(self, profile: dict, selected: str = "") -> None:
        self.profile, self.selected = profile, selected
        self.refresh(recompose=True)

    def render(self) -> str:
        return ""

    def on_resize(self, _event: Resize) -> None:
        self.refresh(recompose=True)

    def compose(self) -> ComposeResult:
        width, height = self.content_size
        if width < 10 or height < 5:
            return
        yield Static(grid(width, height), classes="grid")
        outputs = daemon.placed(self.profile)
        rects = [(o, o.get("x", 0), o.get("y", 0), *daemon.logical_size(o)) for o in outputs]
        if not rects:
            return
        left, top = min(r[1] for r in rects), min(r[2] for r in rects)
        span_x = max(r[1] + r[3] for r in rects) - left
        span_y = max(r[2] + r[4] for r in rects) - top
        cell = max(span_x / (width - 4), span_y / (height - 2) / CELL_ASPECT)
        row_height = cell * CELL_ASPECT
        pad_x, pad_y = (width - span_x / cell) / 2, (height - span_y / row_height) / 2
        for output, x, y, w, h in rects:
            column, line = round(pad_x + (x - left) / cell), round(pad_y + (y - top) / row_height)
            region = Region(column, line, max(12, round(w / cell)), max(7, round(h / row_height)))
            yield Card(self.body(output), output["key"], cell, region, output["key"] == self.selected)


class TabLine(Widget):
    def render(self) -> Text:
        line = Text("─", GRAY["grid"])
        for number, (tab, title) in enumerate(TABS.items(), 1):
            if tab == self.app.tab:
                line.append(f" {number} {title} ", "bold green")
            else:
                line.append(f" {number}", f"bold {GRAY['label']}").append(f" {title} ")
            line.append("─", GRAY["grid"])
        setup = self.app.setup_label().append("─", GRAY["grid"])
        rule = "─" * max(0, self.size.width - line.cell_len - setup.cell_len)
        return line.append(rule, GRAY["grid"]).append(setup)


class MonitorEditor(App):
    TITLE = "hyprmoncfg"
    AUTO_FOCUS = "#canvas"
    ENABLE_COMMAND_PALETTE = False
    CSS = """
    TabLine, #footer { height: 1; }
    ContentSwitcher, ContentSwitcher > Horizontal { height: 1fr; }
    .panel { border: round $frame; border-title-color: $label; padding: 0 1; background: transparent; }
    .panel:focus, .panel:focus-within { border: round ansi_green; border-title-color: ansi_green; border-title-style: bold; }
    .side { width: 52; }
    Canvas { width: 1fr; height: 1fr; }
    #inspector, #profile-list, #workspace-list { height: 1fr; }
    #info, #details, #plan { height: auto; }
    .grid { position: absolute; color: $grid; }
    Card {
        position: absolute; border: round $frame; content-align: center middle;
        text-align: center; text-wrap: nowrap; text-overflow: ellipsis;
    }
    Card.selected { border: round ansi_green; }
    OptionList, OptionList:focus { background: transparent; background-tint: transparent; max-height: 100%; }
    OptionList > .option-list--option-highlighted, OptionList:focus > .option-list--option-highlighted {
        background: transparent; color: ansi_green; text-style: bold;
    }
    #profile-list { border: none; padding: 0; }
    #auto-row { margin-bottom: 1; }
    #hints { width: 1fr; }
    #version { width: auto; }
    Prompt, Help { align: center middle; }
    .dialog { width: 72; height: auto; border: round $frame; padding: 1 2; }
    .dialog Input { border: round $frame; background: transparent; }
    .dialog Input:focus { border: round ansi_green; }
    """
    BINDINGS = [
        ("1", "show_tab('layout')"), ("2", "show_tab('profiles')"), ("3", "show_tab('workspaces')"),
        Binding("tab", "next_pane", priority=True),
        ("left", "adjust(-1)"), ("right", "adjust(1)"), ("a", "apply"), ("s", "save"), ("r", "reset"),
        ("y", "finish_preview(True)"), ("n", "finish_preview(False)"), ("l", "load"), ("e", "edit_exec"),
        ("d", "delete"), ("space", "toggle_auto"), ("question_mark", "help"), ("q", "quit"),
    ]
    PROFILE_ACTIONS = {"load", "edit_exec", "delete", "toggle_auto"}

    def __init__(self) -> None:
        super().__init__()
        self.draft, self.displays, self.status, self.saved = {}, [], {}, {}
        self.selected, self.source, self.page = "", "", "display"
        self.tab_line, self.switcher = TabLine(), ContentSwitcher(initial="layout")
        self.canvas = Canvas(mode_card, editable=True, id="canvas")
        self.profile_canvas, self.workspace_canvas = Canvas(mode_card), Canvas(self.workspace_card)
        self.info, self.details = Static(id="info", classes="panel"), Static(id="details", classes="panel")
        self.plan_view = Static(id="plan", classes="panel")
        self.inspector = OptionList(id="inspector", classes="panel")
        self.auto_row, self.profile_list = Static(id="auto-row"), OptionList(id="profile-list")
        self.workspace_list = OptionList(id="workspace-list", classes="panel side")
        self.hints = Static(id="hints")

    def compose(self) -> ComposeResult:
        yield self.tab_line
        with self.switcher:
            with Horizontal(id="layout"):
                yield self.canvas
                with Vertical(classes="side"):
                    yield self.info
                    yield self.inspector
            with Horizontal(id="profiles"):
                with Vertical(id="saved", classes="panel side"):
                    yield self.auto_row
                    yield Static(Text(f"  {'Profile':<40}{'Match':>6}", GRAY["label"]))
                    yield self.profile_list
                with Vertical():
                    yield self.details
                    yield self.profile_canvas
            with Horizontal(id="workspaces"):
                yield self.workspace_list
                with Vertical():
                    yield self.plan_view
                    yield self.workspace_canvas
        with Horizontal(id="footer"):
            yield self.hints
            yield Static(Text(f"v{VERSION}", GRAY["label"]), id="version")

    def get_theme_variable_defaults(self) -> dict[str, str]:
        return GRAY

    def on_mount(self) -> None:
        self.theme = "ansi-light" if LIGHT else "ansi-dark"
        titles = {
            "#saved": "Saved Profiles", "#info": "Info", "#details": "Profile Details",
            "#plan": "Workspace Plan", "#workspace-list": "Workspace Planner",
        }
        for selector, title in titles.items():
            self.query_one(selector).border_title = title
        self.action_reset()
        self.follow_daemon()

    @work(exclusive=True)
    async def follow_daemon(self) -> None:
        reader, writer = await asyncio.open_unix_connection(daemon.SOCKET_PATH, limit=1 << 22)
        writer.write(frame("subscribe"))
        while line := await reader.readline():
            message = json.loads(line)
            self.status = message.get("result") or message.get("data") or self.status
            self.show_status()
        self.notify("hyprmoncfgd stopped", severity="error")

    def check_action(self, action: str, parameters: tuple) -> bool:
        if isinstance(self.screen, ModalScreen):
            return False
        if action in self.PROFILE_ACTIONS:
            return self.tab == "profiles"
        if action == "next_pane":
            return self.tab == "layout"
        if action == "finish_preview":
            return bool(self.preview)
        if action == "adjust":
            return self.focused in (self.inspector, self.workspace_list)
        return True

    @property
    def tab(self) -> str:
        return self.switcher.current or "layout"

    @property
    def output(self) -> dict:
        return next((o for o in self.draft.get("outputs", []) if o["key"] == self.selected), {})

    @property
    def display(self) -> dict:
        return next((d for d in self.displays if d["key"] == self.selected), {})

    @property
    def preview(self) -> dict | None:
        return self.status.get("daemon", {}).get("preview")

    @property
    def automatic(self) -> bool:
        return "profile_override" not in self.status.get("daemon", {})

    @property
    def chosen_name(self) -> str:
        option = self.profile_list.highlighted_option
        return option.id if option else ""

    def name_of(self, key: str) -> str:
        return next((o.get("name", key) for o in self.draft.get("outputs", []) if o["key"] == key), key)

    def model_by_key(self, key: str) -> str:
        return next((model_of(o) for o in self.draft.get("outputs", []) if o["key"] == key), key)

    def send(self, method: str, **params) -> dict | None:
        reply = request(method, params) or {"error": {"message": "hyprmoncfgd is not running"}}
        if "error" in reply:
            self.notify(reply["error"]["message"], severity="error")
            return None
        return reply["result"]

    def edit(self, **edit) -> None:
        try:
            self.draft = daemon.edit_profile(self.draft, edit)
        except ValueError as error:
            self.notify(str(error), severity="warning")
        self.redraw()

    def edit_output(self, **fields) -> None:
        self.edit(output_key=self.selected, **fields)

    def ask(self, heading: str, label: str, value: str, then: Callable, kind: str = "text") -> None:
        self.push_screen(Prompt(heading, label, value, kind), lambda answer: answer is None or then(answer))

    def reselect(self) -> None:
        keys = [o["key"] for o in self.draft.get("outputs", [])]
        focused = (d["key"] for d in self.displays if d.get("focused") and d["key"] in keys)
        self.selected = next(focused, keys[0] if keys else "")

    def setup_label(self) -> Text:
        if self.preview:
            label = ("Previewing ", self.preview["profile_name"], " · y keeps · n reverts")
        else:
            active = (self.status.get("active_profile") or {}).get("name") or "none"
            label = ("Current setup · ", active, "" if self.automatic else " · manual")
        return Text.assemble((label[0], GRAY["label"]), (label[1], "bold green"), (label[2], GRAY["label"]))

    def redraw(self) -> None:
        self.canvas.border_title = f"Monitor Layout  {self.hidden_displays()}".rstrip()
        self.canvas.show(self.draft, self.selected)
        self.info.update(self.info_text())
        self.refresh_inspector()
        fill(self.workspace_list, self.workspace_rows())
        rules_on = self.draft.get("workspaces", {}).get("enabled")
        note = [] if rules_on else ["(workspace rules disabled; preview only)", ""]
        self.plan_view.update(Text("\n").join(map(Text, note + plan_lines(planned(self.draft)))))
        self.workspace_canvas.show(self.draft)

    def refresh_inspector(self) -> None:
        fields = self.output_fields()
        fill(self.inspector, [option(*fields[field][:2], field) for field in PAGES[self.page] if field in fields])
        title = [Text(page.capitalize(), "bold green" if page == self.page else GRAY["label"]) for page in PAGES]
        self.inspector.border_title = Text(" - ").join(title)

    def show_status(self) -> None:
        self.saved = {p["name"]: p for p in profiles.load_all()}
        auto = ("on", "bold green") if self.automatic else ("off", GRAY["label"])
        self.auto_row.update(Text.assemble(f"{'Automatic profile selection':<46}", auto))
        summaries = self.status.get("profiles", [])
        fill(self.profile_list, [Option(profile_row(s), id=s["name"]) for s in summaries])
        lid = hypr.lid_state()
        self.canvas.border_subtitle = f"Lid: {lid}" if lid else ""
        self.show_profile()
        self.tab_line.refresh()
        self.update_hints()

    def show_profile(self) -> None:
        summary = next((s for s in self.status.get("profiles", []) if s["name"] == self.chosen_name), None)
        profile = self.saved.get(self.chosen_name)
        details = self.profile_details(summary, profile) if summary and profile else "No saved profiles"
        self.details.update(details)
        self.profile_canvas.show(profile or {})

    def update_hints(self) -> None:
        spec = HINTS.get(getattr(self.focused, "id", ""), HINTS["canvas"])
        self.hints.update(hint_line(("y keep|n revert|" if self.preview else "") + spec))

    def hidden_displays(self) -> str:
        outputs = [OUTPUT_DEFAULTS | o for o in self.draft.get("outputs", [])]
        mirrors = [o for o in outputs if o["enabled"] and o["mirror_of"]]
        groups = {
            "off": [o["name"] for o in outputs if not o["enabled"]],
            "mirroring": [f"{o['name']} → {self.name_of(o['mirror_of'])}" for o in mirrors],
        }
        return "  ".join(f"{label}: {', '.join(names)}" for label, names in groups.items() if names)

    def info_text(self) -> Text:
        if not self.output:
            return Text()
        output, display = OUTPUT_DEFAULTS | self.output, self.display
        width, height = daemon.logical_size(output)
        size = f"{display.get('physical_width', 0)} x {display.get('physical_height', 0)} mm"
        panel = size if display else "(not connected)"
        return table([
            ("Connector", output.get("name", "")),
            ("Type", "Internal display" if hypr.is_internal(output) else "External display"),
            ("Model", model_of(output)),
            ("Serial", display.get("serial") or "(none)"),
            ("Layout px", f"{width} x {height}"),
            ("Workspace", display.get("workspace", "")),
            ("DPMS", "on" if display.get("dpms") else "off"),
            ("Panel mm", panel),
        ], 11)

    def profile_details(self, summary: dict, profile: dict) -> Text:
        standing = ("Active", "bold green") if summary["active"] else ("Saved", "bold")
        match = Text.assemble(standing, (" · score ", GRAY["label"]), str(summary["match_score"]))
        reasons = [("", reason_line(reason)) for reason in summary["match_reasons"]]
        plan = plan_lines(profile) if profile.get("workspaces", {}).get("enabled") else ["(not managed)"]
        return table([
            ("Name", Text(profile["name"], "bold")),
            ("Updated", profile.get("updated_at", "")[:16].replace("T", " ")),
            ("Match", match),
            *reasons,
            ("Displays", f"{summary['output_count']} saved · {summary['connected_outputs']} connected"),
            ("Exec", profile.get("exec") or "(not set)"),
            *(("Workspaces" if index == 0 else "", line) for index, line in enumerate(plan)),
        ], 11)

    def workspace_card(self, output: dict) -> Text:
        rows = workspaces.plan(planned(self.draft))
        numbers = next((", ".join(r["workspaces"]) for r in rows if r["output_key"] == output["key"]), "")
        name, model = (output.get("name", ""), "bold"), (model_of(output), GRAY["label"])
        return Text.assemble(name, "\n", model, "\n", (numbers, "green"))

    def output_fields(self) -> dict[str, tuple[str, object, Callable[[int], object]]]:
        if not self.output:
            return {}
        o, display = OUTPUT_DEFAULTS | self.output, self.display
        modes = display.get("available_modes") or [o["mode"]]
        scales = sorted({*display.get("scale_options", []), o["scale"]})
        mirrors = ["", *(p["key"] for p in daemon.placed(self.draft) if p["key"] != o["key"])]
        mirror, brightness, saturation = o["mirror_of"], o["sdr_brightness"], o["sdr_saturation"]
        vrr = o.get("vrr")
        return {
            "enabled": ("Enabled", "on" if o["enabled"] else "off", lambda d: not o["enabled"]),
            "mode": ("Mode", o["mode"], lambda d: cycle(modes, o["mode"], d)),
            "scale": ("Scale", f"{o['scale']:g}", lambda d: cycle(scales, o["scale"], d)),
            "vrr": ("VRR", "default" if vrr is None else VRR_MODES[vrr], lambda d: cycle(range(3), vrr, d)),
            "transform": ("Rotation", ROTATIONS[o["transform"]], lambda d: (o["transform"] + d) % 8),
            "x": ("Position X", o["x"], lambda d: o["x"] + 10 * d),
            "y": ("Position Y", o["y"], lambda d: o["y"] + 10 * d),
            "mirror_of": ("Mirror", self.name_of(mirror) or "None", lambda d: cycle(mirrors, mirror, d)),
            "bitdepth": ("Bit depth", f"{o['bitdepth']}-bit", lambda d: cycle((8, 10), o["bitdepth"], d)),
            "cm": ("Color", o["cm"], lambda d: cycle(COLOR_MODES, o["cm"], d)),
            "sdr_brightness": ("SDR brightness", f"{brightness:.2f}", lambda d: sdr_step(brightness, d)),
            "sdr_saturation": ("SDR saturation", f"{saturation:.2f}", lambda d: sdr_step(saturation, d)),
        }

    def workspace_rows(self) -> list[Option]:
        settings = self.draft.get("workspaces", {})
        strategy, rules = settings.get("strategy", "sequential"), settings.get("rules", [])
        manual = strategy == "manual"
        rows = [
            option("Enabled", "on" if settings.get("enabled") else "off", "enabled"),
            option("Strategy", strategy, "strategy"),
            option("Max workspaces", len(rules) if manual else settings.get("max_workspaces", 9), "count"),
        ]
        if strategy == "sequential":
            rows.append(option("Group size", settings.get("group_size", 3), "group_size"))
        heading = Text("Assignments    ←/→ reassigns" if manual else "Monitor order  ←/→ reorders", GRAY["label"])
        rows += [Option(" ", disabled=True), Option(heading, disabled=True)]
        if manual:
            return rows + [
                option(f"  Workspace {rule['workspace']}", self.model_by_key(rule["output_key"]), f"rule:{i}")
                for i, rule in enumerate(rules)
            ]
        return rows + [
            Option(f"  {i + 1}. {self.model_by_key(key)}", id=f"order:{i}")
            for i, key in enumerate(workspaces.target_keys(self.draft))
        ]

    def adjust_workspaces(self, option_id: str, delta: int) -> None:
        settings = dict(self.draft.get("workspaces", {}))
        rules, keys = [dict(r) for r in settings.get("rules", [])], workspaces.target_keys(self.draft)
        kind, _, index = option_id.partition(":")
        if kind == "enabled":
            settings["enabled"] = not settings.get("enabled")
        elif kind == "strategy":
            settings["strategy"] = cycle(STRATEGIES, settings.get("strategy", "sequential"), delta)
            if settings["strategy"] == "manual" and not rules:
                seeded = workspaces.rules(planned(self.draft))
                settings["rules"] = sorted(seeded, key=lambda rule: int(rule["workspace"]))
        elif kind == "count" and settings.get("strategy") == "manual":
            if delta > 0:
                rules.append({"workspace": str(len(rules) + 1), "output_key": next(iter(keys), "")})
            elif len(rules) > 1:
                rules.pop()
            settings["rules"] = rules
        elif kind in ("count", "group_size"):
            field, default = ("max_workspaces", 9) if kind == "count" else ("group_size", 3)
            settings[field] = max(1, settings.get(field, default) + delta)
        elif kind == "rule":
            rules[int(index)]["output_key"] = cycle(keys, rules[int(index)]["output_key"], delta)
            settings["rules"] = rules
        elif kind == "order" and 0 <= int(index) + delta < len(keys):
            moved = int(index)
            keys[moved], keys[moved + delta] = keys[moved + delta], keys[moved]
            settings["monitor_order"] = keys
            self.edit(workspaces=settings)
            self.workspace_list.highlighted += delta
            return
        self.edit(workspaces=settings)

    def on_descendant_focus(self, _event: DescendantFocus) -> None:
        self.update_hints()

    def on_option_list_option_highlighted(self, event: OptionList.OptionHighlighted) -> None:
        if event.option_list is self.profile_list:
            self.show_profile()

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        field = event.option.id
        if event.option_list is self.profile_list:
            self.action_apply()
        elif event.option_list is self.inspector and field in ("x", "y"):
            place = lambda text: self.edit_output(**{field: int(text)})
            label = f"Position {field.upper()}"
            self.ask(label, "Logical pixels", str(self.output.get(field, 0)), place, "integer")
        else:
            self.action_adjust(1)

    def action_show_tab(self, tab: str) -> None:
        self.switcher.current = tab
        {"layout": self.canvas, "profiles": self.profile_list, "workspaces": self.workspace_list}[tab].focus()
        if tab == "profiles":
            self.saved = {p["name"]: p for p in profiles.load_all()}
            self.show_profile()
        self.tab_line.refresh()

    def action_next_pane(self) -> None:
        if self.focused is self.canvas:
            self.page = "display"
            self.inspector.focus()
        elif self.focused is self.inspector and self.page == "display":
            self.page = "color"
        else:
            self.canvas.focus()
            return
        self.refresh_inspector()
        self.inspector.highlighted = 0

    def action_help(self) -> None:
        self.push_screen(Help())

    def action_adjust(self, delta: int) -> None:
        option = self.focused.highlighted_option
        if option and self.focused is self.inspector:
            self.edit_output(**{option.id: self.output_fields()[option.id][2](delta)})
        elif option:
            self.adjust_workspaces(option.id, delta)

    def action_nudge(self, dx: int, dy: int) -> None:
        self.edit_output(x=self.output.get("x", 0) + dx, y=self.output.get("y", 0) + dy)

    def action_snap(self, direction: str) -> None:
        self.edit_output(snap_beside=direction)

    def action_origin(self) -> None:
        self.edit_output(x=0, y=0)

    def action_select_output(self, delta: int) -> None:
        self.selected = cycle([o["key"] for o in self.draft.get("outputs", [])], self.selected, delta)
        self.redraw()

    def drop(self, key: str, dx: float, dy: float, tolerance: float) -> None:
        self.selected = key
        x, y = self.output.get("x", 0), self.output.get("y", 0)
        self.edit_output(x=round(x + dx), y=round(y + dy), snap_distance=tolerance if dx or dy else 0)

    def action_reset(self) -> None:
        editor = self.send("editor_state")
        if editor:
            self.draft, self.displays = editor["profile"], editor["displays"]
            self.source = editor["source_profile"]
            self.reselect()
            self.redraw()

    def preview_draft(self, name: str, save: bool) -> None:
        profile = {**self.draft, "name": name}
        self.send("preview", profile=profile, timeout_seconds=PREVIEW_SECONDS, save_on_commit=save)

    def action_apply(self) -> None:
        if self.tab == "profiles":
            self.send("preview", profile_name=self.chosen_name, timeout_seconds=PREVIEW_SECONDS)
        else:
            self.preview_draft(self.source or "draft", save=False)

    def action_save(self) -> None:
        self.ask("Save Profile", "Name", self.source, self.save_as)

    def save_as(self, name: str) -> None:
        if name:
            self.source = name
            self.preview_draft(name, save=True)

    def action_finish_preview(self, keep: bool) -> None:
        transaction = self.preview["transaction_id"]
        if keep:
            self.send("commit", transaction_id=transaction, save=self.preview["save_on_commit"])
        else:
            self.send("revert", transaction_id=transaction)

    def action_load(self) -> None:
        profile = self.saved.get(self.chosen_name)
        if profile:
            self.draft, self.source = profile, profile["name"]
            self.reselect()
            self.redraw()
            self.action_show_tab("layout")

    def action_edit_exec(self) -> None:
        profile = self.saved.get(self.chosen_name)
        if profile:
            save = lambda command: self.send("save", profile={**profile, "exec": command})
            self.ask("Profile Exec", "Command to run after applying", profile.get("exec", ""), save)

    def action_delete(self) -> None:
        self.send("delete", name=self.chosen_name)

    def action_toggle_auto(self) -> None:
        self.send("set_profile_auto", enabled=not self.automatic)


def run() -> int:
    if request("status") is None:
        print("hyprmoncfgd is not running.", file=sys.stderr)
        return 1
    MonitorEditor().run()
    return 0
