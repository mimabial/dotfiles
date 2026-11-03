import functools
import logging
import os
import subprocess
from pathlib import Path

from binding_source import HYPRCTL_TIMEOUT_SECONDS, get_hyprctl_binds
from binding_metadata import annotate_bindings_with_display_metadata
from hint_formats import format_submap_hint
from pyutils.hyprctl import batch_json
from pyutils.xdg_base_dirs import xdg_state_home
from pyutils.shell_env import load_shell_assignments

LOG = logging.getLogger("submap-hint")

STATE_FILE = Path(os.environ.get("HYPR_STATE_HOME") or xdg_state_home() / "hypr") / "staterc"



# keybindings.lua tags binds a submap re-exposes from the global set with this
# prefix: they work inside the submap but stay out of its hint. Change both.
HIDDEN_MARKER = "[Hidden] "



# keybindings.lua gates these binds on the workspace layout at press time, inside
# a Lua closure that hyprctl cannot see: every bind reports dispatcher "__lua".
# The sub-category header is the only signal that a bind is layout-specific.
LAYOUT_HEADERS = {
    "Dwindle": "dwindle",
    "Master": "master",
    "Scrolling": "scrolling",
    "Monocle": "monocle",
}

ARROW_HEADERS = ("Focus", "Move", "Resize")
DIRECTIONS = ("left", "right", "up", "down")
OPPOSITE = {"left": "right", "right": "left", "up": "down", "down": "up"}
DIRECTION_VECTORS = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}
AXIS_DIRECTIONS = (("left", "right"), ("up", "down"))
GROW_AXIS = {"right": 0, "down": 1}
SCROLL_ROTATION = {
    "right": {"left": "left", "right": "right", "up": "up", "down": "down"},
    "left": {"left": "right", "right": "left", "up": "up", "down": "down"},
    "up": {"up": "right", "down": "left", "left": "up", "right": "down"},
    "down": {"up": "left", "down": "right", "left": "up", "right": "down"},
}
FIT_METHOD_FIT = 1
STICKS_PX = 2
MFACT_MIN, MFACT_MAX = 0.05, 0.95
COLUMN_WIDTH_MIN, COLUMN_WIDTH_MAX = 0.05, 1.0
RATIO_EPSILON = 1e-3

OPTION_NAMES = (
    "general:border_size",
    "general:no_focus_fallback",
    "binds:window_direction_monitor_fallback",
    "master:allow_small_split",
    "master:slave_count_for_center_master",
    "scrolling:direction",
    "scrolling:explicit_column_widths",
    "scrolling:focus_fit_method",
    "scrolling:fullscreen_on_one_column",
    "scrolling:wrap_focus",
    "scrolling:wrap_swapcol",
)

TILED_LAYOUT_LUA = """
local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
local rows = {}
for _, window in ipairs(workspace and hl.get_workspace_windows(workspace) or {}) do
    local layout = window.mapped and window.layout
    local column = layout and layout.column
    if layout then
        rows[#rows + 1] = string.format(
            '{"address":"%s","is_master":%s,"perc_master":%s,"column":%s,"column_width":%s,"row":%s,"column_size":%s}',
            window.address, tostring(layout.is_master == true), layout.perc_master or "null",
            column and column.index or "null", column and column.width or "null",
            layout.index_in_column or "null", column and #column.windows or "null")
    end
end
return "[" .. table.concat(rows, ",") .. "]"
"""



def normalize_submap(name):
    name = name.strip()
    return "" if name.casefold() in {"", "default", "reset"} else name



def active_tiled_layout(monitors, workspaces):
    """Mirrors layout_action in keybindings.lua: a special workspace, when one is
    open on the focused monitor, owns the layout the gate compares against."""
    focused = next((m for m in monitors if m.get("focused")), None)
    if focused is None:
        return None
    special = (focused.get("specialWorkspace") or {}).get("name") or ""
    wanted = special or (focused.get("activeWorkspace") or {}).get("name") or ""
    if not wanted:
        return None
    for workspace in workspaces:
        if workspace.get("name") == wanted:
            return workspace.get("tiledLayout")
    return None



def applies_to_layout(bind, layout):
    required = LAYOUT_HEADERS.get(bind.get("header2", ""))
    return required is None or required == layout



def option_value(reply):
    return next(value for key, value in reply.items() if key not in ("option", "set"))



def monitor_edges(monitor):
    width, height = monitor["width"] / monitor["scale"], monitor["height"] / monitor["scale"]
    if monitor["transform"] % 2:
        width, height = height, width
    return {"left": monitor["x"], "up": monitor["y"], "right": monitor["x"] + width, "down": monitor["y"] + height}



def has_monitor_toward(direction, monitor, monitors):
    edge = monitor_edges(monitor)[direction]
    return any(
        abs(monitor_edges(other)[OPPOSITE[direction]] - edge) < STICKS_PX
        for other in monitors
        if other["id"] != monitor["id"]
    )



def lies_toward(direction, origin, other):
    offset = [other["at"][axis] + other["size"][axis] / 2 - origin["at"][axis] - origin["size"][axis] / 2 for axis in (0, 1)]
    vector = DIRECTION_VECTORS[direction]
    return offset[0] * vector[0] + offset[1] * vector[1] >= 0



class WindowContext:
    def __init__(self, layout, window, clients, monitors, tiled_rows, options):
        self.layout = layout
        self.options = options
        self.window = window if window.get("address") else None
        self.monitor = next(monitor for monitor in monitors if monitor.get("focused"))
        self.toward = {
            direction
            for direction in DIRECTIONS
            if options["binds:window_direction_monitor_fallback"] and has_monitor_toward(direction, self.monitor, monitors)
        }
        self.column_widths = [float(width) for width in options["scrolling:explicit_column_widths"].split(",")]
        self.tiled = {row["address"]: row for row in tiled_rows}
        self.scroll_direction = self.placed_scroll_direction(clients)
        self.scroll_axis = 0 if self.scroll_direction in AXIS_DIRECTIONS[0] else 1
        self.active = self.tiled.get(self.window["address"]) if self.window else None
        self.other_tiled = len(self.tiled) - bool(self.active)
        self.masters = [row for row in tiled_rows if row["is_master"]]
        self.columns = len({row["column"] for row in tiled_rows})
        self.peers = [
            client
            for client in clients
            if self.window
            and client["workspace"]["id"] == self.window["workspace"]["id"]
            and client["address"] != self.window["address"]
            and client["mapped"]
            and not client["hidden"]
        ]

    @property
    def paired(self):
        return bool(self.active) and self.other_tiled > 0

    @property
    def splittable(self):
        return self.paired and not self.window["fullscreen"]

    @property
    def stack(self):
        return len(self.tiled) - len(self.masters)

    @property
    def centers_without_stack(self):
        return self.options["master:slave_count_for_center_master"] == 0

    @property
    def master_resizable(self):
        return bool(self.window) and (self.stack > 0 or self.centers_without_stack)

    @property
    def stacked(self):
        return bool(self.active) and self.active["column_size"] > 1

    @property
    def has_next_column(self):
        return bool(self.active) and self.active["column"] < self.columns - 1

    @property
    def column_resizable(self):
        return bool(self.active) and not (self.options["scrolling:fullscreen_on_one_column"] and self.columns == 1)

    def column_swap_reaches(self, step):
        if not self.active or self.columns < 2:
            return False
        return self.options["scrolling:wrap_swapcol"] or 0 <= self.active["column"] + step < self.columns

    def column_focus_reaches(self, step):
        if not self.active:
            return False
        fallback = not self.options["general:no_focus_fallback"]
        if self.scroll_axis:
            index, count, wraps = self.active["row"], self.active["column_size"], fallback
        else:
            index, count, wraps = self.active["column"], self.columns, fallback and self.options["scrolling:wrap_focus"]
        return count > 1 and (wraps or 0 <= index + step < count)

    def placed_scroll_direction(self, clients):
        configured = self.options["scrolling:direction"]
        heads, first_column = {}, []
        for client in clients:
            row = self.tiled.get(client["address"])
            if row and row["row"] == 0:
                heads[row["column"]] = client["at"]
            if row and row["column"] == 0:
                first_column.append(client)
        if len(heads) > 1:
            (x0, y0), (x1, y1) = heads[0], heads[1]
            if x0 != x1:
                return "right" if x1 > x0 else "left"
            return "down" if y1 > y0 else "up"
        if len(first_column) > 1:
            horizontal = first_column[0]["at"][0] == first_column[1]["at"][0]
        elif first_column and self.tiled[first_column[0]["address"]]["column_width"] < COLUMN_WIDTH_MAX - RATIO_EPSILON:
            fill = [first_column[0]["size"][axis] / (end - start) for axis, (start, end) in enumerate(map(self.screen_span, (0, 1)))]
            horizontal = fill[0] < fill[1]
        else:
            return configured
        if (configured in AXIS_DIRECTIONS[0]) == horizontal:
            return configured
        return "right" if horizontal else "down"

    def screen_span(self, axis):
        start, end = AXIS_DIRECTIONS[axis]
        edges, reserved = monitor_edges(self.monitor), self.monitor["reserved"]
        return edges[start] + reserved[axis], edges[end] - reserved[axis + 2]

    def primary_span(self, client):
        start = client["at"][self.scroll_axis]
        return start, start + client["size"][self.scroll_axis]

    def column_in_view(self):
        low, high = self.screen_span(self.scroll_axis)
        start, end = self.primary_span(self.window)
        if self.options["scrolling:focus_fit_method"] == FIT_METHOD_FIT:
            return low <= start and end <= high
        return abs(start + end - low - high) / 2 < STICKS_PX

    def expanded_column_width(self):
        low, high = self.screen_span(self.scroll_axis)
        visible_widths = {}
        for peer in self.peers:
            row = self.tiled.get(peer["address"])
            start, end = self.primary_span(peer)
            if row and row["column"] != self.active["column"] and start < high and end > low:
                visible_widths[row["column"]] = row["column_width"]
        return min(max(1 - sum(visible_widths.values()), 0), 1)



LAYOUT_ROW_RULES = {
    ("Monocle", "focus next"): lambda ctx: ctx.other_tiled > 0,
    ("Monocle", "focus previous"): lambda ctx: ctx.other_tiled > 0,
    ("Dwindle", "toggle window split"): lambda ctx: ctx.splittable,
    ("Dwindle", "swap split"): lambda ctx: ctx.splittable,
    ("Dwindle", "rotate split"): lambda ctx: ctx.splittable,
    ("Dwindle", "move to root"): lambda ctx: ctx.splittable and ctx.other_tiled > 1,
    ("Dwindle", "shrink parent split"): lambda ctx: ctx.splittable,
    ("Dwindle", "grow parent split"): lambda ctx: ctx.splittable,
    ("Master", "focus master"): lambda ctx: bool(ctx.window) and ctx.other_tiled > 0,
    ("Master", "swap with master"): lambda ctx: ctx.paired,
    ("Master", "focus next"): lambda ctx: ctx.paired,
    ("Master", "focus previous"): lambda ctx: ctx.paired,
    ("Master", "swap next"): lambda ctx: ctx.paired if ctx.active else bool(ctx.peers),
    ("Master", "swap previous"): lambda ctx: ctx.paired if ctx.active else bool(ctx.peers),
    ("Master", "add master"): lambda ctx: bool(ctx.active)
    and ctx.stack > (0 if ctx.options["master:allow_small_split"] else 1),
    ("Master", "remove master"): lambda ctx: bool(ctx.active) and len(ctx.masters) > 1,
    ("Master", "cycle orientation"): lambda ctx: bool(ctx.window)
    and (len(ctx.tiled) > 1 or (len(ctx.tiled) == 1 and ctx.centers_without_stack)),
    ("Master", "center orientation"): lambda ctx: bool(ctx.window)
    and (len(ctx.tiled) > 1 or (len(ctx.tiled) == 1 and ctx.centers_without_stack)),
    ("Master", "roll next"): lambda ctx: bool(ctx.active) and ctx.stack > 0,
    ("Master", "roll previous"): lambda ctx: bool(ctx.active) and ctx.stack > 0,
    ("Master", "shrink master"): lambda ctx: ctx.master_resizable
    and max(row["perc_master"] for row in ctx.masters) > MFACT_MIN + RATIO_EPSILON,
    ("Master", "grow master"): lambda ctx: ctx.master_resizable
    and min(row["perc_master"] for row in ctx.masters) < MFACT_MAX - RATIO_EPSILON,
    ("Scrolling", "scroll view to previous column"): lambda ctx: ctx.active["column"] > 0 if ctx.active else bool(ctx.tiled),
    ("Scrolling", "scroll view to next column"): lambda ctx: ctx.has_next_column,
    ("Scrolling", "swap column left"): lambda ctx: ctx.column_swap_reaches(-1),
    ("Scrolling", "swap column right"): lambda ctx: ctx.column_swap_reaches(1),
    ("Scrolling", "focus previous column"): lambda ctx: ctx.column_focus_reaches(-1),
    ("Scrolling", "focus next column"): lambda ctx: ctx.column_focus_reaches(1),
    ("Scrolling", "shrink column"): lambda ctx: ctx.column_resizable
    and ctx.active["column_width"] > min(ctx.column_widths) + RATIO_EPSILON,
    ("Scrolling", "grow column"): lambda ctx: ctx.column_resizable
    and ctx.active["column_width"] < max(ctx.column_widths) - RATIO_EPSILON,
    ("Scrolling", "expand column"): lambda ctx: ctx.column_resizable
    and abs(ctx.expanded_column_width() - ctx.active["column_width"]) > RATIO_EPSILON,
    ("Scrolling", "promote window"): lambda ctx: ctx.stacked,
    ("Scrolling", "consume into column"): lambda ctx: ctx.has_next_column,
    ("Scrolling", "expel from column"): lambda ctx: ctx.stacked,
    ("Scrolling", "fit column into view"): lambda ctx: bool(ctx.active) and not ctx.column_in_view(),
}



def floating_resizable(window, monitor, border_size):
    reserved_left, reserved_top, reserved_right, reserved_bottom = monitor["reserved"]
    edges = monitor_edges(monitor)
    limit = (
        edges["right"] - edges["left"] - reserved_left - reserved_right - 2 * border_size,
        edges["down"] - edges["up"] - reserved_top - reserved_bottom - 2 * border_size,
    )
    return {"left", "up"} | {direction for direction, axis in GROW_AXIS.items() if window["size"][axis] < limit[axis]}



def floating_focusable(ctx):
    floats = [peer for peer in ctx.peers if peer["floating"] or peer["fullscreen"]]
    if floats and not ctx.options["general:no_focus_fallback"]:
        return set(DIRECTIONS)
    return ctx.toward | {direction for direction in DIRECTIONS if any(lies_toward(direction, ctx.window, peer) for peer in floats)}



def scrolling_movable(ctx):
    column, row, size = ctx.active["column"], ctx.active["row"], ctx.active["column_size"]
    reachable = {
        "left": column > 0 or size > 1,
        "right": column < ctx.columns - 1 or size > 1,
        "up": row > 0,
        "down": row < size - 1,
    }
    return {direction for direction in DIRECTIONS if reachable[SCROLL_ROTATION[ctx.scroll_direction][direction]]}



def acting_arrow_rows(ctx):
    if not ctx.window:
        focus, move, resize = ctx.toward, (), ()
    elif not ctx.active:
        focus = floating_focusable(ctx)
        move, resize = DIRECTIONS, floating_resizable(ctx.window, ctx.monitor, ctx.options["general:border_size"])
    elif ctx.layout == "monocle":
        focus, move, resize = ctx.toward, ctx.toward, ()
    elif ctx.layout == "scrolling":
        focus = DIRECTIONS if ctx.peers else ctx.toward
        move = scrolling_movable(ctx) | ctx.toward
        shrink, grow = AXIS_DIRECTIONS[ctx.scroll_axis]
        width = ctx.active["column_width"]
        strip_steps = {shrink: width > COLUMN_WIDTH_MIN + RATIO_EPSILON, grow: width < COLUMN_WIDTH_MAX - RATIO_EPSILON}
        resize = {direction for direction, acts in strip_steps.items() if acts and ctx.column_resizable}
        resize |= set(AXIS_DIRECTIONS[1 - ctx.scroll_axis]) if ctx.stacked else set()
    else:
        focus = DIRECTIONS if ctx.peers else ctx.toward
        move = DIRECTIONS if (ctx.peers if ctx.layout == "master" else ctx.other_tiled) else ctx.toward
        lone_master_resizes = ctx.layout == "master" and ctx.centers_without_stack
        resize = DIRECTIONS if ctx.other_tiled or lone_master_resizes else ()
    if ctx.window and ctx.window["fullscreen"]:
        resize = ()
    rows = {"Focus": focus, "Move": move, "Resize": resize}
    return {(header, direction) for header, directions in rows.items() for direction in directions}



def acts_now(bind, ctx, arrows):
    header = bind.get("header2", "")
    if header in ARROW_HEADERS:
        return (header, bind["key"].lower()) in arrows
    rule = LAYOUT_ROW_RULES.get((header, bind["action_key"].split("] ", 1)[-1]))
    return rule is None or rule(ctx)



def binds_acting_now(binds):
    monitors, workspaces, window, clients, *option_replies, tiled_rows = batch_json(
        "monitors",
        "workspaces",
        "activewindow",
        "clients",
        *(f"getoption {name}" for name in OPTION_NAMES),
        f"repl {TILED_LAYOUT_LUA}",
        timeout=HYPRCTL_TIMEOUT_SECONDS,
    )
    layout = active_tiled_layout(monitors, workspaces)
    if layout is None:
        return binds
    options = {reply["option"]: option_value(reply) for reply in option_replies}
    ctx = WindowContext(layout, window, clients, monitors, tiled_rows, options)
    arrows = acting_arrow_rows(ctx)
    return [bind for bind in binds if applies_to_layout(bind, layout) and acts_now(bind, ctx, arrows)]



@functools.cache
def configured_binds():
    binds = get_hyprctl_binds()
    annotate_bindings_with_display_metadata(binds)
    return binds


def build_submap_hint(name):
    submap_binds = [bind for bind in configured_binds() if bind.get("submap") == name]
    if not submap_binds:
        raise RuntimeError(f"no configured binds found for submap {name!r}")
    # The annotation rewrites description; action_key keeps the original.
    submap_binds = [
        bind for bind in submap_binds if not bind.get("action_key", "").startswith(HIDDEN_MARKER)
    ]
    if not submap_binds:
        return ""
    state = load_shell_assignments(STATE_FILE) if STATE_FILE.is_file() else {}
    workflow = state.get("HYPR_WORKFLOW", "")
    profile_locked = os.getenv("HYPR_PROFILE_WORKFLOW_LOCK", "1") != "0"
    blocked = {
        "gaming": ("bar", "select workflow"),
        "powersaver": ("select workflow",) if profile_locked else (),
        "windows": ("toggle bar",),
    }.get(workflow, ())
    if state.get("WORKFLOW_WINDOW_LAYOUT"):
        blocked += ("global layout",)
    if len(state.get("WORKFLOW_QUICKSHELL_LAYOUT", "").split()) == 1:
        blocked += ("bar layout",)
    if blocked:
        submap_binds = [bind for bind in submap_binds if not any(text in bind["action_key"] for text in blocked)]
    try:
        submap_binds = binds_acting_now(submap_binds)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        LOG.error("window state lookup failed, showing all binds: %s", error)
    return format_submap_hint(submap_binds)
