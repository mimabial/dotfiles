"""Which screen edge the active Quickshell bar occupies."""

import os
from pathlib import Path

from pyutils.shell_env import load_shell_assignments

QUICKSHELL_EDGE = {
    "main": "right",
    "left": "left",
    "sidebar": "left",
    "top": "top",
    "winbar": "bottom",
}

STATE_FILE = (
    Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr")) / "staterc"
)
def bar_position():
    """Return the edge the bar sits on: left, right, top or bottom."""
    try:
        layout = load_shell_assignments(STATE_FILE).get("QUICKSHELL_LAYOUT_NAME", "")
    except OSError:
        layout = ""
    return QUICKSHELL_EDGE.get(layout, "right")
