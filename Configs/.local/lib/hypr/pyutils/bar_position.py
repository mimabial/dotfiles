import json
import os
from pathlib import Path

from pyutils.shell_env import load_shell_assignments

STATE_FILE = (
    Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr")) / "staterc"
)
LAYOUT_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "quickshell/layouts"
BAR_PREFS = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "quickshell/bar.json"


def bar_position(layout=None):
    if layout is None:
        try:
            layout = load_shell_assignments(STATE_FILE).get("QUICKSHELL_LAYOUT_NAME", "")
        except OSError:
            layout = ""
    try:
        layout_data = json.loads((LAYOUT_DIR / f"{layout}.json").read_text())
        edge = layout_data["edge"]
        if layout_data.get("panel") == "winbar" and BAR_PREFS.exists():
            edge = json.loads(BAR_PREFS.read_text()).get("winbarEdge") or edge
    except (OSError, KeyError, TypeError, ValueError):
        edge = "top"
    return edge if edge in {"top", "bottom"} else "top"
