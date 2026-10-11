"""Where each agent CLI keeps the local data the usage scanners read."""
from __future__ import annotations

from pathlib import Path
import os

from pyutils.xdg_base_dirs import xdg_data_home

OPENCODE_DATA_DIR = xdg_data_home() / "opencode"
OPENCODE_DB = OPENCODE_DATA_DIR / "opencode.db"
CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
PI_SESSION_ROOTS = (
  Path.home() / ".pi" / "agent" / "sessions",
  Path.home() / ".omp" / "agent" / "sessions",
)
