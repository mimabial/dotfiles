"""Shared helpers for render/*.py renderers."""

import os
import subprocess
import tempfile
from pathlib import Path


def cache_hit(app: str, h: str) -> bool:
    return subprocess.run(["render-cache", "hit?", app, h]).returncode == 0


def cache_store(app: str, h: str) -> None:
    subprocess.run(["render-cache", "store", app, h])


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.replace(tmp, path)
    finally:
        if Path(tmp).exists():
            try:
                Path(tmp).unlink()
            except FileNotFoundError:
                pass
