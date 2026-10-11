import os
from pathlib import Path

from pyutils.xdg_base_dirs import xdg_runtime_dir, xdg_state_home

def ensure_runtime_root_dir() -> Path:
    root = xdg_runtime_dir() or Path(f"/run/user/{os.getuid()}")
    try:
        root.mkdir(parents=True, exist_ok=True)
    except OSError:
        root = xdg_state_home() / "hypr/runtime"
        root.mkdir(parents=True, exist_ok=True)
    return root


def runtime_lock_path_ensure_parent(operation: str) -> Path:
    return ensure_runtime_root_dir() / f"{operation.replace('_', '-')}.lock"
