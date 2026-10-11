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



def normalize_submap(name):
    name = name.strip()
    return "" if name.casefold() in {"", "default", "reset"} else name



def active_tiled_layout(monitors=None, workspaces=None):
    """Mirrors layout_action in keybindings.lua: a special workspace, when one is
    open on the focused monitor, owns the layout the gate compares against."""
    if monitors is None or workspaces is None:
        monitors, workspaces = batch_json("monitors", "workspaces", timeout=HYPRCTL_TIMEOUT_SECONDS)
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



def build_submap_hint(name):
    binds = get_hyprctl_binds()
    try:
        layout = active_tiled_layout()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        LOG.error("layout lookup failed, showing all binds: %s", error)
        layout = None
    annotate_bindings_with_display_metadata(binds)
    submap_binds = [bind for bind in binds if bind.get("submap") == name]
    # The annotation rewrites description; action_key keeps the original.
    submap_binds = [
        bind for bind in submap_binds if not bind.get("action_key", "").startswith(HIDDEN_MARKER)
    ]
    state = load_shell_assignments(STATE_FILE) if STATE_FILE.is_file() else {}
    workflow = state.get("HYPR_WORKFLOW", "")
    profile_locked = os.getenv("HYPR_PROFILE_WORKFLOW_LOCK", "1") != "0"
    blocked = {
        "gaming": ("bar", "select workflow"),
        "powersaver": ("select workflow",) if profile_locked else (),
        "windows": ("toggle bar",),
    }.get(workflow, ())
    if state.get("WORKFLOW_WINDOW_LAYOUT"):
        blocked += ("cycle global layout",)
    if len(state.get("WORKFLOW_QUICKSHELL_LAYOUT", "").split()) == 1:
        blocked += ("bar layout",)
    if blocked:
        submap_binds = [bind for bind in submap_binds if not any(text in bind["action_key"] for text in blocked)]
    if layout is not None:
        submap_binds = [
            bind for bind in submap_binds if applies_to_layout(bind, layout)
        ]
    return format_submap_hint(submap_binds)

