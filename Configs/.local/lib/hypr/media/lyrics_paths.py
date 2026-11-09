from __future__ import annotations

import os
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils.xdg_base_dirs import xdg_config_home

HIDDEN_LYRICS_DIR_NAME = ".lyrics"


def absolute_path(path: str | Path) -> Path:
    expanded = os.path.expandvars(os.path.expanduser(os.fspath(path)))
    return Path(os.path.abspath(expanded))


def _music_dir_from_user_dirs() -> str | None:
    user_dirs = xdg_config_home() / "user-dirs.dirs"
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
    return music_library_dir() / HIDDEN_LYRICS_DIR_NAME


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
    path = absolute_path(file_path)
    library = music_library_dir()
    hidden = library / HIDDEN_LYRICS_DIR_NAME
    if path.is_relative_to(hidden) or not path.is_relative_to(library):
        return path.with_suffix(".lrc")
    return (hidden / path.relative_to(library)).with_suffix(".lrc")


def prune_empty_lyrics_parents(path: Path) -> None:
    stop = hidden_lyrics_root()
    current = path
    while current != stop and stop in current.parents:
        try:
            current.rmdir()
        except OSError:
            return
        current = current.parent


def lyrics_directory_for(directory: str | Path) -> Path | None:
    path = absolute_path(directory)
    library = music_library_dir()
    if not path.is_relative_to(library):
        return None
    return library / HIDDEN_LYRICS_DIR_NAME / path.relative_to(library)
