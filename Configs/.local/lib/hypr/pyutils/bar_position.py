"""Which screen edge the active Quickshell bar occupies."""

import json
import os
from pathlib import Path

from pyutils.shell_env import load_shell_assignments

STATE_FILE = (
    Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr")) / "staterc"
)
LAYOUT_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "quickshell/layouts"


def bar_position():
    """Return the top or bottom edge occupied by the bar."""
    try:
        layout = load_shell_assignments(STATE_FILE).get("QUICKSHELL_LAYOUT_NAME", "")
    except OSError:
        layout = ""
    try:
        edge = json.loads((LAYOUT_DIR / f"{layout}.json").read_text())["edge"]
    except (OSError, KeyError, TypeError, ValueError):
        edge = "top"
    return edge if edge in {"top", "bottom"} else "top"
