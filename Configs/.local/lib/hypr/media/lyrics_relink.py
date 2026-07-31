#!/usr/bin/env python3
"""Relink orphaned LRC files to audio files after unmanaged moves."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

from fetch_album_lyrics import get_audio_metadata
from lyrics_paths import (
    absolute_path,
    hidden_lyrics_root,
    is_in_hidden_lyrics,
    is_in_music_library,
    lrc_path_for,
    music_library_dir,
)

DEFAULT_EXTENSIONS = "mp3,flac,m4a,ogg,opus"
LRC_TAG = re.compile(r"^\[(ar|al|ti):(.*)]\s*$", re.IGNORECASE)


@dataclass(frozen=True)
class LrcEntry:
    path: Path
    artist: str
    title: str
    album: str
    owner_key: str


def parse_extensions(raw: str) -> set[str]:
    return {
        "." + value.strip().lstrip(".").casefold()
        for value in raw.split(",")
        if value.strip()
    }


def path_stem_key(path: Path) -> str:
    return str(absolute_path(path).with_suffix("")).casefold()


def lrc_owner_key(path: Path) -> str:
    candidate = absolute_path(path)
    if is_in_hidden_lyrics(candidate):
        relative = candidate.relative_to(hidden_lyrics_root())
        return path_stem_key(music_library_dir() / relative)
    return path_stem_key(candidate)


def read_lrc_entry(path: Path) -> LrcEntry:
    tags = {"ar": "", "ti": "", "al": ""}
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = LRC_TAG.match(line.strip())
            if match:
                tags[match.group(1).casefold()] = match.group(2).strip()
            if tags["ar"] and tags["ti"] and tags["al"]:
                break
    except OSError:
        pass
    return LrcEntry(
        path=path,
        artist=tags["ar"],
        title=tags["ti"],
        album=tags["al"],
        owner_key=lrc_owner_key(path),
    )


def collect_audio_files(
    directory: Path,
    recursive: bool,
    extensions: set[str],
) -> list[Path]:
    iterator = directory.rglob("*") if recursive else directory.iterdir()
    return sorted(
        path
        for path in iterator
        if path.is_file() and path.suffix.casefold() in extensions
    )


def library_audio_keys(extensions: set[str]) -> set[str]:
    return {
        path_stem_key(path)
        for path in music_library_dir().rglob("*")
        if path.is_file()
        and not is_in_hidden_lyrics(path)
        and path.suffix.casefold() in extensions
    }


def library_lrc_entries() -> list[LrcEntry]:
    return [
        read_lrc_entry(path)
        for path in sorted(music_library_dir().rglob("*.lrc"))
        if path.is_file()
    ]


def _same(left: str, right: str) -> bool:
    return bool(left.strip()) and left.strip().casefold() == right.strip().casefold()


def _metadata_matches(entry: LrcEntry, metadata: dict) -> bool:
    artist = str(metadata.get("artist") or "")
    title = str(metadata.get("title") or "")
    album = str(metadata.get("album") or "")
    if not (_same(entry.artist, artist) and _same(entry.title, title)):
        return False
    return not entry.album or not album or _same(entry.album, album)


def find_relink_candidate(
    audio_file: Path,
    entries: list[LrcEntry],
    audio_keys: set[str],
) -> tuple[LrcEntry | None, list[LrcEntry]]:
    current_key = path_stem_key(audio_file)
    available = [
        entry
        for entry in entries
        if entry.owner_key == current_key or entry.owner_key not in audio_keys
    ]
    metadata = get_audio_metadata(audio_file)
    metadata_matches = [
        entry for entry in available if _metadata_matches(entry, metadata)
    ]
    basename_matches = [
        entry
        for entry in available
        if entry.path.stem.casefold() == audio_file.stem.casefold()
    ]

    if len(metadata_matches) == 1:
        return metadata_matches[0], []
    if len(metadata_matches) > 1:
        narrowed = [
            entry
            for entry in metadata_matches
            if entry.path.stem.casefold() == audio_file.stem.casefold()
        ]
        if len(narrowed) == 1:
            return narrowed[0], []
        return None, narrowed or metadata_matches
    if len(basename_matches) == 1:
        return basename_matches[0], []
    if len(basename_matches) > 1:
        return None, basename_matches
    return None, []


def _prune_empty_hidden_parents(path: Path) -> None:
    stop = hidden_lyrics_root()
    current = path
    while current != stop and stop in current.parents:
        try:
            current.rmdir()
        except OSError:
            return
        current = current.parent


def relink_directory(
    directory: Path,
    *,
    recursive: bool,
    dry_run: bool,
    extensions: set[str],
) -> int:
    audio_files = collect_audio_files(directory, recursive, extensions)
    if not audio_files:
        print(f"No supported audio files in {directory}", file=sys.stderr)
        return 0

    audio_keys = library_audio_keys(extensions)
    entries = library_lrc_entries()
    moved = present = missing = ambiguous = 0

    for audio_file in audio_files:
        target = lrc_path_for(audio_file)
        if target.is_file():
            print(f"✓ {audio_file.name}: lyrics already in the correct folder")
            present += 1
            continue

        candidate, conflicts = find_relink_candidate(audio_file, entries, audio_keys)
        if candidate is None:
            if conflicts:
                paths = ", ".join(str(entry.path) for entry in conflicts)
                print(f"! {audio_file.name}: multiple matching lyrics: {paths}")
                ambiguous += 1
            else:
                print(f"✗ {audio_file.name}: no lyrics found")
                missing += 1
            continue

        verb = "Would move" if dry_run else "Moved"
        print(f"{verb}: {candidate.path}\n      -> {target}")
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(candidate.path), str(target))
            _prune_empty_hidden_parents(candidate.path.parent)
        entries.remove(candidate)
        moved += 1

    print(
        f"\nSummary: {moved} {'would move' if dry_run else 'moved'}, "
        f"{present} already correct, {missing} without lyrics, "
        f"{ambiguous} ambiguous"
    )
    return 1 if missing or ambiguous else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="hyprshell media/lyrics_relink",
        description=(
            "Find orphaned lyrics for audio files in a directory and move them "
            "to the correct mirrored lyrics folder"
        ),
    )
    parser.add_argument(
        "directory",
        nargs="?",
        default=str(music_library_dir()),
        help=f"Directory to inspect (default: {music_library_dir()})",
    )
    parser.add_argument(
        "-r",
        "--recursive",
        action="store_true",
        help="Inspect audio files recursively",
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Report moves without changing files",
    )
    parser.add_argument(
        "--ext",
        default=DEFAULT_EXTENSIONS,
        help=f"Comma-separated audio extensions (default: {DEFAULT_EXTENSIONS})",
    )
    args = parser.parse_args()

    directory = absolute_path(args.directory)
    if not directory.is_dir():
        parser.error(f"not a directory: {directory}")
    if not is_in_music_library(directory) or is_in_hidden_lyrics(directory):
        parser.error(f"directory must be inside {music_library_dir()}")
    extensions = parse_extensions(args.ext)
    if not extensions:
        parser.error("--ext produced no extensions")

    return relink_directory(
        directory,
        recursive=args.recursive,
        dry_run=args.dry_run,
        extensions=extensions,
    )


if __name__ == "__main__":
    raise SystemExit(main())
