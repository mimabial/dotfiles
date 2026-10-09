from __future__ import annotations

import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from lyrics_paths import (
    absolute_path,
    hidden_lyrics_root,
    is_in_hidden_lyrics,
    is_in_music_library,
    lrc_path_for,
    lyrics_directory_for,
)


class MoveError(RuntimeError):
    pass


@dataclass(frozen=True)
class MovePlan:
    source: Path
    target: Path
    lyrics_source: Path | None
    lyrics_target: Path | None
    move_lyrics: bool

    @property
    def has_lyrics(self) -> bool:
        return self.move_lyrics


def _effective_target(source: Path, destination: str | Path) -> Path:
    destination_path = absolute_path(destination)
    if destination_path.is_dir():
        return destination_path / source.name
    return destination_path


def check_move_source(source_path: Path) -> None:
    if not source_path.exists():
        raise MoveError(f"source does not exist: {source_path}")
    if is_in_hidden_lyrics(source_path):
        raise MoveError(f"source is inside the managed lyrics directory: {source_path}")


def check_move_target(source_path: Path, target: Path, require_music_root: bool) -> None:
    if source_path == target:
        raise MoveError("source and destination are the same path")
    if source_path.is_dir() and source_path in target.parents:
        raise MoveError("cannot move a directory inside itself")
    if target.exists():
        raise MoveError(f"destination already exists: {target}")
    if is_in_hidden_lyrics(target):
        raise MoveError(f"destination is inside the managed lyrics directory: {target}")

    source_in_music = is_in_music_library(source_path)
    target_in_music = is_in_music_library(target)
    if require_music_root and (not source_in_music or not target_in_music):
        raise MoveError(
            f"only paths within the music library can be moved: "
            f"{hidden_lyrics_root().parent}"
        )
    if source_in_music != target_in_music:
        raise MoveError("cannot move a managed music path into or out of the library")


def lyrics_paths_for_move(source_path: Path, target: Path) -> tuple[Path | None, Path | None]:
    if source_path.is_dir():
        return lyrics_directory_for(source_path), lyrics_directory_for(target)
    return lrc_path_for(source_path), lrc_path_for(target)


def build_move_plan(
    source: str | Path,
    destination: str | Path,
    *,
    require_music_root: bool = False,
) -> MovePlan:
    source_path = absolute_path(source)
    check_move_source(source_path)
    target = _effective_target(source_path, destination)
    check_move_target(source_path, target, require_music_root)

    lyrics_source, lyrics_target = lyrics_paths_for_move(source_path, target)
    move_lyrics = (
        lyrics_source is not None
        and lyrics_target is not None
        and lyrics_source != lyrics_target
        and lyrics_source.exists()
    )
    if move_lyrics and lyrics_target.exists():
        raise MoveError(f"lyrics destination already exists: {lyrics_target}")
    return MovePlan(source_path, target, lyrics_source, lyrics_target, move_lyrics)


def _prune_empty_lyrics_parents(path: Path) -> None:
    stop = hidden_lyrics_root()
    current = path
    while current != stop and stop in current.parents:
        try:
            current.rmdir()
        except OSError:
            return
        current = current.parent


def apply_move_plan(plan: MovePlan) -> None:
    """Rolls the audio back if its lyrics move fails."""
    plan.target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(plan.source), str(plan.target))

    if not plan.has_lyrics:
        return

    assert plan.lyrics_source is not None
    assert plan.lyrics_target is not None
    try:
        plan.lyrics_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(plan.lyrics_source), str(plan.lyrics_target))
    except OSError as exc:
        try:
            plan.source.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(plan.target), str(plan.source))
        except OSError as rollback_exc:
            raise MoveError(
                f"lyrics move failed ({exc}); audio rollback also failed "
                f"({rollback_exc})"
            ) from exc
        raise MoveError(f"lyrics move failed; audio move was rolled back: {exc}") from exc

    _prune_empty_lyrics_parents(plan.lyrics_source.parent)


def update_mpd() -> None:
    executable = shutil.which("rmpc")
    if executable is None:
        print("Warning: rmpc is unavailable; MPD was not updated", file=sys.stderr)
        return
    result = subprocess.run(
        [executable, "update"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or f"exit status {result.returncode}"
        print(f"Warning: MPD update failed: {detail}", file=sys.stderr)
