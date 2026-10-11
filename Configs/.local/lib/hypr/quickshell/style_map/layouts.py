import json
import sys
from functools import cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils.xdg_base_dirs import xdg_config_home

QUICKSHELL_CONFIG_DIR = xdg_config_home() / "quickshell"

BAR_COMPONENT_TYPES = {"horizontal": "HorizontalBar", "winbar": "HorizontalBar"}


@cache
def read_layout(layout):
    data = json.loads((QUICKSHELL_CONFIG_DIR / "layouts" / f"{layout}.json").read_text())
    if data.get("extends"):
        shared = json.loads((QUICKSHELL_CONFIG_DIR / "layouts" / "shared" / f"{data['extends']}.json").read_text())
        data = {**shared, **data}
    return data


def layout_modules(layout):
    data = read_layout(layout)
    entries = [m for key in ("left", "center", "right") for m in data.get(key, [])]
    return [(e, {}) if isinstance(e, str) else (e.get("id", ""), e.get("props") or {})
            for e in entries]
