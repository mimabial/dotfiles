import os
from pathlib import Path


HOME = Path.home()
LIB_DIR = Path(os.environ.get("HYPR_LIB_DIR") or HOME / ".local/lib/hypr")
STATE_DIR = Path(os.environ.get("HYPR_STATE_HOME") or HOME / ".local/state/hypr")
CONFIG_DIR = Path(os.environ.get("HYPR_CONFIG_HOME") or HOME / ".config/hypr")
DATA_DIR = Path(os.environ.get("HYPR_DATA_HOME") or HOME / ".local/share/hypr")
READER = str(LIB_DIR / "window/looknfeel-read.lua")


def library_command(path, *arguments):
    return [str(LIB_DIR / path), *arguments]
