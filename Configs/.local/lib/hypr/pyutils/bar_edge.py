import json
import os
from pathlib import Path

from pyutils.shell_env import load_shell_assignments
from pyutils.xdg_base_dirs import xdg_config_home, xdg_state_home

STATE_ASSIGNMENTS_PATH = Path(os.environ.get("HYPR_STATE_HOME", xdg_state_home() / "hypr")) / "staterc"
LAYOUTS_DIR = xdg_config_home() / "quickshell/layouts"
BAR_PREFERENCES_PATH = xdg_state_home() / "quickshell/bar.json"
BAR_EDGES = {"top", "bottom"}
DEFAULT_BAR_EDGE = "top"


def bar_edge(layout_name: str | None = None) -> str:
    if layout_name is None:
        try:
            layout_name = load_shell_assignments(STATE_ASSIGNMENTS_PATH).get("QUICKSHELL_LAYOUT_NAME", "")
        except OSError:
            layout_name = ""
    try:
        layout_data = json.loads((LAYOUTS_DIR / f"{layout_name}.json").read_text())
        edge = layout_data["edge"]
        if layout_data.get("panel") == "winbar" and BAR_PREFERENCES_PATH.exists():
            edge = json.loads(BAR_PREFERENCES_PATH.read_text()).get("winbarEdge") or edge
    except (OSError, KeyError, TypeError, ValueError):
        edge = DEFAULT_BAR_EDGE
    return edge if edge in BAR_EDGES else DEFAULT_BAR_EDGE
