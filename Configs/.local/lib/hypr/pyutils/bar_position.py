"""Which screen edge the active bar occupies.

Quickshell owns the bar and records its layout in staterc. The waybar config is
only consulted when that key is missing, since waybar is disabled — reading it
first is what left dunst rendering to the wrong edge.
"""

import os
import re
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
WAYBAR_CONF = (
    Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
    / "waybar"
    / "config.jsonc"
)


def bar_position():
    """Return the edge the bar sits on: left, right, top or bottom."""
    try:
        layout = load_shell_assignments(STATE_FILE).get("WAYBAR_LAYOUT_NAME", "")
    except OSError:
        layout = ""
    if layout:
        return QUICKSHELL_EDGE.get(layout, "right")

    try:
        for line in WAYBAR_CONF.read_text().splitlines():
            match = re.search(r'"position"\s*:\s*"([^"]*)"', line)
            if match:
                return match.group(1)
    except OSError:
        pass
    return "right"
