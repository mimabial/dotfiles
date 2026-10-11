from __future__ import annotations

from pathlib import Path
from typing import Any
import json
import os
import tempfile
import time

from pyutils.xdg_base_dirs import xdg_cache_home

def usage_cache_dir() -> Path:
  root = Path(os.environ.get("HYPR_CACHE_HOME") or xdg_cache_home() / "hypr") / "agents"
  root.mkdir(parents=True, exist_ok=True)
  return root


def read_cached_json(path: Path) -> Any:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception:
    return None


def read_fresh_cached_json(path: Path, max_age_seconds: float) -> dict[str, Any] | None:
  if max_age_seconds <= 0 or not path.exists():
    return None
  try:
    if 0 <= time.time() - path.stat().st_mtime <= max_age_seconds:
      return json.loads(path.read_text(encoding="utf-8"))
  except Exception:
    return None
  return None


def write_cached_json(path: Path, payload: dict[str, Any]) -> None:
  handle_fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
  tmp = Path(tmp_name)
  try:
    with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
      handle.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
    tmp.chmod(0o644)
    tmp.replace(path)
  except BaseException:
    tmp.unlink(missing_ok=True)
    raise
