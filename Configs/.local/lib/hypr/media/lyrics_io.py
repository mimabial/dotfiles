#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path

HEADER_TAG_RE = re.compile(r"^\[(ar|al|ti):.*\]\s*$", re.IGNORECASE)


def normalize_lrc(lyrics: str, artist: str, title: str, album: str) -> str:
    body_lines = []
    for raw_line in lyrics.splitlines():
        if HEADER_TAG_RE.match(raw_line.strip()):
            continue
        body_lines.append(raw_line)

    normalized_lines = [
        f"[ar:{artist}]",
        f"[al:{album}]",
        f"[ti:{title}]",
    ]
    normalized_lines.extend(body_lines)
    return "\n".join(normalized_lines) + "\n"


def write_lrc_atomic(path: str | Path, content: str) -> None:
    target = Path(path).expanduser()
    target.parent.mkdir(parents=True, exist_ok=True)

    fd, temp_path = tempfile.mkstemp(prefix=".lrc.", suffix=".tmp", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, target)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def save_lrc(path: str | Path, lyrics: str, artist: str, title: str, album: str) -> None:
    normalized = normalize_lrc(lyrics, artist, title, album)
    write_lrc_atomic(path, normalized)
