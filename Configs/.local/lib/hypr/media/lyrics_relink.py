#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import os
import re
import shutil
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import NamedTuple

from audio_tags import parse_extensions
from lyrics_metadata import DEFAULT_EXTENSIONS, get_audio_metadata
from lyrics_paths import (
    absolute_path,
    hidden_lyrics_root,
    is_in_hidden_lyrics,
    is_in_music_library,
    lrc_path_for,
    lyrics_directory_for,
    music_library_dir,
    prune_empty_lyrics_parents,
)

LRC_TAG = re.compile(r"^\[(ar|al|ti):(.*)]\s*$", re.IGNORECASE)


@dataclass(frozen=True)
class LrcEntry:
    path: Path
    artist: str
    title: str
    album: str
    owner_key: str


@dataclass
class LibraryIndex:
    audio_files: list[Path]
    audio_keys: set[str]
    by_metadata: dict[tuple[str, str], list[LrcEntry]]
    by_basename: dict[str, list[LrcEntry]]
    active_paths: set[Path]

    def available_lyrics_entries(
        self,
        entries: list[LrcEntry],
        current_key: str,
    ) -> list[LrcEntry]:
        return sorted(
            (
                entry
                for entry in entries
                if entry.path in self.active_paths
                and (
                    entry.owner_key == current_key
                    or entry.owner_key not in self.audio_keys
                )
            ),
            key=lambda entry: entry.path,
        )

    def remove(self, entry: LrcEntry) -> None:
        self.active_paths.discard(entry.path)


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


def _metadata_key(artist: str, title: str) -> tuple[str, str]:
    return artist.strip().casefold(), title.strip().casefold()


def _audio_is_in_scope(
    path: Path,
    directory: Path,
    recursive: bool,
) -> bool:
    return directory in path.parents if recursive else path.parent == directory


def build_library_index(
    directory: Path,
    recursive: bool,
    extensions: set[str],
) -> LibraryIndex:
    audio_files: list[Path] = []
    audio_keys: set[str] = set()
    by_metadata: dict[tuple[str, str], list[LrcEntry]] = defaultdict(list)
    by_basename: dict[str, list[LrcEntry]] = defaultdict(list)
    active_paths: set[Path] = set()

    for path in music_library_dir().rglob("*"):
        if not path.is_file():
            continue
        suffix = path.suffix.casefold()
        if suffix in extensions and not is_in_hidden_lyrics(path):
            audio_keys.add(path_stem_key(path))
            if _audio_is_in_scope(path, directory, recursive):
                audio_files.append(path)
            continue
        if suffix != ".lrc":
            continue

        entry = read_lrc_entry(path)
        active_paths.add(entry.path)
        by_basename[entry.path.stem.casefold()].append(entry)
        key = _metadata_key(entry.artist, entry.title)
        if all(key):
            by_metadata[key].append(entry)

    audio_files.sort()
    return LibraryIndex(
        audio_files=audio_files,
        audio_keys=audio_keys,
        by_metadata=dict(by_metadata),
        by_basename=dict(by_basename),
        active_paths=active_paths,
    )


def _same_nonempty_metadata_value(left: str, right: str) -> bool:
    return bool(left.strip()) and left.strip().casefold() == right.strip().casefold()


def _metadata_matches(entry: LrcEntry, metadata: dict) -> bool:
    artist = str(metadata.get("artist") or "")
    title = str(metadata.get("title") or "")
    album = str(metadata.get("album") or "")
    if not (_same_nonempty_metadata_value(entry.artist, artist) and _same_nonempty_metadata_value(entry.title, title)):
        return False
    return not entry.album or not album or _same_nonempty_metadata_value(entry.album, album)


def find_relink_candidate(
    audio_file: Path,
    index: LibraryIndex,
) -> tuple[LrcEntry | None, list[LrcEntry]]:
    current_key = path_stem_key(audio_file)
    metadata = get_audio_metadata(audio_file)
    metadata_key = _metadata_key(
        str(metadata.get("artist") or ""),
        str(metadata.get("title") or ""),
    )
    metadata_matches = [
        entry
        for entry in index.available_lyrics_entries(
            index.by_metadata.get(metadata_key, []),
            current_key,
        )
        if _metadata_matches(entry, metadata)
    ]
    basename_matches = index.available_lyrics_entries(
        index.by_basename.get(audio_file.stem.casefold(), []),
        current_key,
    )

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


class RelinkOutcome(Enum):
    PRESENT = "present"
    MOVED = "moved"
    AMBIGUOUS = "ambiguous"
    MISSING = "missing"


class LyricsMirrorTidy(NamedTuple):
    relinked: int
    deleted: int


def relink_audio_file(
    audio_file: Path,
    index: LibraryIndex,
    dry_run: bool,
) -> tuple[RelinkOutcome, list[LrcEntry]]:
    target = lrc_path_for(audio_file)
    if target.is_file():
        return RelinkOutcome.PRESENT, []

    candidate, conflicts = find_relink_candidate(audio_file, index)
    if candidate is None:
        if not conflicts:
            return RelinkOutcome.MISSING, []
        paths = ", ".join(str(entry.path) for entry in conflicts)
        print(f"! {audio_file.name}: multiple matching lyrics: {paths}")
        return RelinkOutcome.AMBIGUOUS, conflicts

    verb = "Would move" if dry_run else "Moved"
    print(f"{verb}: {candidate.path}\n      -> {target}")
    if not dry_run:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(candidate.path), str(target))
        prune_empty_lyrics_parents(candidate.path.parent)
    index.remove(candidate)
    return RelinkOutcome.MOVED, [candidate]


def relink_directory(
    directory: Path,
    *,
    recursive: bool,
    dry_run: bool,
    extensions: set[str],
) -> int:
    index = build_library_index(directory, recursive, extensions)
    if not index.audio_files:
        print(f"No supported audio files in {directory}", file=sys.stderr)
        return 0

    outcomes: Counter[RelinkOutcome] = Counter()
    for audio_file in index.audio_files:
        outcome, _ = relink_audio_file(audio_file, index, dry_run)
        if outcome is RelinkOutcome.PRESENT:
            print(f"✓ {audio_file.name}: lyrics already in the correct folder")
        elif outcome is RelinkOutcome.MISSING:
            print(f"✗ {audio_file.name}: no lyrics found")
        outcomes[outcome] += 1

    print(
        f"\nSummary: {outcomes[RelinkOutcome.MOVED]} {'would move' if dry_run else 'moved'}, "
        f"{outcomes[RelinkOutcome.PRESENT]} already correct, "
        f"{outcomes[RelinkOutcome.MISSING]} without lyrics, "
        f"{outcomes[RelinkOutcome.AMBIGUOUS]} ambiguous"
    )
    return 1 if outcomes[RelinkOutcome.MISSING] or outcomes[RelinkOutcome.AMBIGUOUS] else 0


def behind_broken_link(directory: Path) -> bool:
    nearest = next(path for path in (directory, *directory.parents) if os.path.lexists(path))
    return nearest.is_symlink() and not nearest.exists()


def prune_orphaned_lyrics(
    lyrics_directory: Path,
    recursive: bool,
    claimed: set[Path],
    dry_run: bool,
) -> int:
    lyrics_files = lyrics_directory.rglob("*.lrc") if recursive else lyrics_directory.glob("*.lrc")
    deleted = 0
    for lyrics_file in sorted(lyrics_files):
        audio_stem = music_library_dir() / lyrics_file.relative_to(hidden_lyrics_root()).with_suffix("")
        if (
            lyrics_file in claimed
            or behind_broken_link(audio_stem.parent)
            or any(audio_stem.parent.glob(f"{glob.escape(audio_stem.name)}.*"))
        ):
            continue
        print(f"{'Would delete' if dry_run else 'Deleted'} orphaned lyrics: {lyrics_file}")
        if not dry_run:
            lyrics_file.unlink()
            prune_empty_lyrics_parents(lyrics_file.parent)
        deleted += 1
    return deleted


def tidy_lyrics_mirror(
    directory: Path,
    recursive: bool,
    extensions: set[str],
    dry_run: bool,
) -> LyricsMirrorTidy:
    lyrics_directory = lyrics_directory_for(directory)
    if lyrics_directory is None or is_in_hidden_lyrics(directory):
        return LyricsMirrorTidy(0, 0)
    index = build_library_index(directory, recursive, extensions)
    relinked = 0
    claimed: set[Path] = set()
    for audio_file in index.audio_files:
        outcome, entries = relink_audio_file(audio_file, index, dry_run)
        relinked += outcome is RelinkOutcome.MOVED
        claimed.update(entry.path for entry in entries)
    return LyricsMirrorTidy(relinked, prune_orphaned_lyrics(lyrics_directory, recursive, claimed, dry_run))


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="hyprshell media/lyrics_relink",
        description="Find orphaned lyrics for audio files in a directory and move them to the correct mirrored lyrics folder",
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
