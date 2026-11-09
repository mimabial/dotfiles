from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

from mutagen import File as MutagenFile
from mutagen import MutagenError

DEFAULT_EXTENSIONS = "mp3,flac,m4a,ogg,opus"


def _first_tag(tags, *wanted: str) -> str:
    normalized = {
        re.sub(r"[\s_-]+", "", str(key).casefold()): value
        for key, value in tags.items()
    }
    for key in wanted:
        value = normalized.get(re.sub(r"[\s_-]+", "", key.casefold()))
        if isinstance(value, (list, tuple)):
            value = value[0] if value else ""
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def get_audio_metadata(file_path: str | Path) -> dict[str, Any]:
    empty = {
        "title": "",
        "artist": "",
        "album_artist": "",
        "album": "",
        "duration": 0.0,
    }
    try:
        audio = MutagenFile(file_path, easy=True)
        if audio is None:
            return empty
        tags = audio.tags or {}
        info = getattr(audio, "info", None)
        return {
            "title": _first_tag(tags, "title"),
            "artist": _first_tag(tags, "artist"),
            "album_artist": _first_tag(tags, "albumartist", "album_artist"),
            "album": _first_tag(tags, "album"),
            "duration": float(getattr(info, "length", 0.0) or 0.0),
        }
    except (MutagenError, OSError, TypeError, ValueError) as exc:
        print(f"Warning: Could not read metadata for {file_path}: {exc}", file=sys.stderr)
        return empty
