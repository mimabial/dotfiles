import os
import tempfile
from pathlib import Path

DIGEST_LENGTH = 16
ANSI_COLOR_COUNT = 16

CACHE_HOME = Path(os.environ.get("HYPR_CACHE_HOME") or Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "hypr")
HASH_DIR = CACHE_HOME / "render-hashes"


def short_digest(hasher) -> str:
    return hasher.hexdigest()[:DIGEST_LENGTH]


def cache_hit(app: str, digest: str) -> bool:
    if os.environ.get("HYPR_FORCE_REGEN") == "1" or not digest:
        return False
    try:
        return (HASH_DIR / app).read_text().strip() == digest
    except OSError:
        return False


def cache_store(app: str, digest: str) -> None:
    if os.environ.get("HYPR_NO_CACHE") != "1":
        atomic_write(HASH_DIR / app, digest + "\n")


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
