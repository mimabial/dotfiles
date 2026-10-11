# The panel compares the CLI's reported version against the running daemon's to
# decide whether the daemon is stale, so both must read the same constant.
VERSION = "2.0.0"

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils.xdg_base_dirs import xdg_config_home

CONFIG_HOME = str(xdg_config_home())
