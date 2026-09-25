"""Shared helpers for render/*.py renderers."""

import os
import subprocess
import tempfile
from pathlib import Path


def cache_hit(app: str, digest: str) -> bool:
    return subprocess.run(["render-cache", "hit?", app, digest]).returncode == 0


def cache_store(app: str, digest: str) -> None:
    subprocess.run(["render-cache", "store", app, digest])


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_path = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    try:
        with os.fdopen(file_descriptor, "w") as output_file:
            output_file.write(content)
        os.replace(temporary_path, path)
    finally:
        if Path(temporary_path).exists():
            try:
                Path(temporary_path).unlink()
            except FileNotFoundError:
                pass
