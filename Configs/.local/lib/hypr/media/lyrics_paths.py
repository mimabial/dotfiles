"""Canonical paths for external lyrics stored below the music library."""

from __future__ import annotations

import os
import shlex
from pathlib import Path


def absolute_path(path: str | Path) -> Path:
    expanded = os.path.expandvars(os.path.expanduser(os.fspath(path)))
    return Path(os.path.abspath(expanded))


def _music_dir_from_user_dirs() -> str | None:
    config_home = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    user_dirs = absolute_path(config_home) / "user-dirs.dirs"
    try:
        lines = user_dirs.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None

    for line in lines:
        try:
            fields = shlex.split(line, comments=True)
        except ValueError:
            continue
        if len(fields) != 1 or not fields[0].startswith("XDG_MUSIC_DIR="):
            continue
        value = fields[0].partition("=")[2]
        return value or None
    return None


def music_library_dir() -> Path:
    configured = os.environ.get("XDG_MUSIC_DIR") or _music_dir_from_user_dirs()
    return absolute_path(configured or Path.home() / "Music")


def hidden_lyrics_root() -> Path:
    return music_library_dir() / ".lyrics"


def is_in_music_library(path: str | Path) -> bool:
    candidate = absolute_path(path)
    try:
        candidate.relative_to(music_library_dir())
    except ValueError:
        return False
    return True


def is_in_hidden_lyrics(path: str | Path) -> bool:
    candidate = absolute_path(path)
    try:
        candidate.relative_to(hidden_lyrics_root())
    except ValueError:
        return False
    return True


def lrc_path_for(file_path: str | Path) -> Path:
    """Return the external LRC path corresponding to an audio file."""
    path = absolute_path(file_path)
    hidden = hidden_lyrics_root()
    if is_in_hidden_lyrics(path):
        return path.with_suffix(".lrc")
    try:
        relative = path.relative_to(music_library_dir())
    except ValueError:
        return path.with_suffix(".lrc")
    return (hidden / relative).with_suffix(".lrc")


def lyrics_directory_for(directory: str | Path) -> Path | None:
    """Return the mirrored lyrics directory for a music-library directory."""
    path = absolute_path(directory)
    try:
        relative = path.relative_to(music_library_dir())
    except ValueError:
        return None
    return hidden_lyrics_root() / relative
