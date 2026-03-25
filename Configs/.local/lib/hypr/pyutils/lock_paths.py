import os
from pathlib import Path

from pyutils.xdg_base_dirs import xdg_runtime_dir

LOCK_NAMES_FILE = Path(__file__).resolve().parent.parent / "runtime" / "lock_names.conf"
_LOCK_NAMES: dict[str, str] | None = None


def load_lock_names() -> dict[str, str]:
    global _LOCK_NAMES
    if _LOCK_NAMES is not None:
        return _LOCK_NAMES

    lock_names: dict[str, str] = {}
    with LOCK_NAMES_FILE.open("r", encoding="utf-8") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            key, value = line.split("=", 1)
            lock_names[key.strip()] = value.strip()

    _LOCK_NAMES = lock_names
    return lock_names


def runtime_lock_name(name: str) -> str:
    template = load_lock_names()[name]
    return template.replace("{uid}", str(os.getuid()))


def runtime_lock_path(name: str) -> Path:
    return Path(xdg_runtime_dir()) / runtime_lock_name(name)
