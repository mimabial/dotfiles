#!/usr/bin/env python3
"""Fetch lyrics for one album or a complete music library."""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter, defaultdict
from enum import Enum
from pathlib import Path
from typing import Any

from mutagen import File as MutagenFile
from mutagen import MutagenError

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lyrics_io import save_lrc
from lyrics_paths import lrc_path_for, music_library_dir
from lyrics_provider import fetch_lyrics
from lyrics_provider_common import _is_lrc_synced, _similarity

DEFAULT_EXTENSIONS = "mp3,flac,m4a,ogg,opus"
TRACK_PREFIX = re.compile(r"^\s*\d{1,3}\s*[-._)]\s*")
BUCKET = re.compile(r"\s*\[(?P<kind>[gc])\]\s*$", re.IGNORECASE)
GENERIC_ALBUM_ARTISTS = {
    "various artists",
    "various artist",
    "various",
    "va",
    "soundtrack",
    "original soundtrack",
    "original motion picture soundtrack",
}
FEATURE_SUFFIX = re.compile(
    r"\s*(?:[\[(]\s*(?:feat\.?|ft\.?|featuring)\s+[^\])]+[\])]|"
    r"(?:feat\.?|ft\.?|featuring)\s+.+)\s*$",
    re.IGNORECASE,
)
NOISE_SUFFIX = re.compile(
    r"\s*(?:[\[(]\s*(?:(?:official\s+)?(?:music\s+|lyric\s+)?video|"
    r"(?:official\s+)?(?:audio|visuali[sz]er)|lyrics?|mv|hd|hq|4k|8k|"
    r"remaster(?:ed)?(?:\s+\d{4})?|explicit|clean|official)\s*[\])]|"
    r"[|:-]\s*(?:(?:official\s+)?(?:music\s+|lyric\s+)?video|"
    r"official\s+(?:audio|visuali[sz]er)))\s*$",
    re.IGNORECASE,
)


class LrcState(Enum):
    MISSING = "missing"
    UNTIMED = "untimed"
    SYNCED = "synced"


class ProcessResult(Enum):
    SAVED = "saved"
    KEPT = "kept"
    SKIPPED = "skipped"
    FAILED = "failed"


def lrc_state(path: Path) -> LrcState:
    if not path.is_file():
        return LrcState.MISSING
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"Warning: Could not read lyrics file {path}: {exc}", file=sys.stderr)
        return LrcState.UNTIMED
    return LrcState.SYNCED if _is_lrc_synced(content) else LrcState.UNTIMED


def should_fetch_lrc(
    state: LrcState,
    force: bool,
    upgrade_plain: bool,
    synced_only: bool = False,
) -> bool:
    if force:
        return True
    if upgrade_plain:
        return state is LrcState.UNTIMED or (
            synced_only and state is LrcState.MISSING
        )
    return state is LrcState.MISSING


def is_generic_album_artist(value: str) -> bool:
    return value.strip().casefold() in GENERIC_ALBUM_ARTISTS


def build_artist_candidates(
    track_artist: str,
    album_artist: str,
    fallback: str,
) -> list[str]:
    candidates: list[str] = []

    def add(value: str) -> None:
        name = (value or "").strip()
        if name and name not in candidates:
            candidates.append(name)

    # The complete track credit is the best identity. Album artist and directory
    # hints are progressively broader fallbacks.
    add(track_artist)
    if album_artist and not is_generic_album_artist(album_artist):
        add(album_artist)
    add(fallback)
    return candidates


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
    """Read tags and duration directly, including Opus stream comments."""
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


def parse_filename(path: Path) -> tuple[str, str]:
    stem = TRACK_PREFIX.sub("", path.stem)
    if " - " not in stem:
        return "", stem.strip()
    artist, _, title = stem.partition(" - ")
    return artist.strip(), title.strip()


def build_title_candidates(
    tagged_title: str,
    filename_title: str,
    artists: list[str],
) -> list[str]:
    """Build one canonical title sequence for interactive and bulk lookups."""
    candidates: list[str] = []

    def add(value: str) -> None:
        value = value.replace("⧸", "/").strip()
        if value and value not in candidates:
            candidates.append(value)

    def without_leading_artist(value: str) -> str:
        for separator in (" - ", " – ", " — "):
            if separator not in value:
                continue
            prefix, title = value.split(separator, 1)
            if title and any(_similarity(prefix, artist) >= 0.5 for artist in artists):
                return title.strip()
        return value

    for raw in (tagged_title, filename_title):
        raw = without_leading_artist(raw.strip())
        clean = NOISE_SUFFIX.sub("", raw).strip(" -–—") or raw
        add(FEATURE_SUFFIX.sub("", clean).strip(" -–—"))
        add(clean)
        add(raw)
    return candidates


def directory_hints(
    file_path: Path,
    scan_root: Path,
    recursive: bool,
) -> tuple[str, str]:
    if not recursive:
        return scan_root.parent.name, scan_root.name

    try:
        parts = file_path.relative_to(scan_root).parts[:-1]
    except ValueError:
        return "", ""
    if not parts:
        return "", ""

    bucket_at = next(
        (index for index, part in enumerate(parts) if BUCKET.search(part)),
        -1,
    )
    if bucket_at >= 0:
        kind = BUCKET.search(parts[bucket_at]).group("kind").casefold()
        inner = parts[bucket_at + 1 :]
        if kind == "c":
            return "", inner[0] if inner else ""
        artist = inner[0] if inner else ""
        album = inner[1] if len(inner) > 1 else ""
        return artist, album

    return parts[0], parts[1] if len(parts) > 1 else ""


def track_identity(
    file_path: Path,
    metadata: dict[str, Any],
    scan_root: Path,
    recursive: bool,
) -> tuple[str, list[str], str, str, float]:
    file_artist, file_title = parse_filename(file_path)
    dir_artist, dir_album = directory_hints(file_path, scan_root, recursive)
    track_artist = str(metadata.get("artist") or file_artist or dir_artist).strip()
    album_artist = str(metadata.get("album_artist") or "").strip()
    fallback_artist = file_artist or dir_artist
    artists = build_artist_candidates(
        track_artist,
        album_artist,
        fallback_artist,
    )
    save_artist = track_artist
    if not save_artist and album_artist and not is_generic_album_artist(album_artist):
        save_artist = album_artist
    save_artist = save_artist or fallback_artist or "Unknown Artist"
    title = str(metadata.get("title") or file_title).strip()
    album = str(metadata.get("album") or dir_album).strip()
    duration = float(metadata.get("duration") or 0.0)
    return save_artist, artists, title, album, duration


def process_audio_file(
    file_path: Path,
    scan_root: Path,
    recursive: bool,
    force: bool = False,
    upgrade_plain: bool = False,
    synced_only: bool = False,
    refresh_cache: bool = False,
    metadata: dict[str, Any] | None = None,
    lrc_file: Path | None = None,
    report_kind: bool = False,
) -> ProcessResult:
    lrc_file = lrc_file or lrc_path_for(file_path)
    state = lrc_state(lrc_file)
    if not should_fetch_lrc(state, force, upgrade_plain, synced_only):
        if upgrade_plain and state is LrcState.SYNCED:
            reason = "already synchronized"
        elif upgrade_plain:
            reason = "no existing .lrc"
        else:
            reason = "already have .lrc"
        print(f"– Skipping {file_path.name} ({reason})")
        return ProcessResult.SKIPPED

    metadata = metadata or get_audio_metadata(file_path)
    artist, artist_candidates, title, album, duration = track_identity(
        file_path,
        metadata,
        scan_root,
        recursive,
    )
    if not title or not artist_candidates:
        print(f'✗ Missing usable identity for: "{file_path.name}"')
        return ProcessResult.FAILED

    print(f"→ Processing: {file_path.name}")
    print(f"  Title: {title}")
    print(f"  Artist: {artist}")
    print(f"  Album: {album}")

    _, filename_title = parse_filename(file_path)
    title_candidates = build_title_candidates(title, filename_title, artist_candidates)
    lyrics = None
    used_artist = ""
    used_title = ""
    for candidate_title in title_candidates:
        for candidate_artist in artist_candidates:
            lyrics = fetch_lyrics(
                candidate_artist,
                candidate_title,
                album,
                fast_mode=False,
                expected_duration=duration,
                refresh_cache=refresh_cache,
                synced_only=upgrade_plain or synced_only,
            )
            if lyrics:
                used_artist, used_title = candidate_artist, candidate_title
                break
        if lyrics:
            break

    if not lyrics:
        if upgrade_plain and state is LrcState.UNTIMED:
            print(f'– No synchronized lyrics found; kept existing file for: "{title}"')
            return ProcessResult.KEPT
        if synced_only:
            print(f'✗ No synchronized lyrics found for: "{title}"')
            return ProcessResult.FAILED
        print(f'✗ No lyrics found for: "{title}"')
        return ProcessResult.FAILED

    if used_artist != artist:
        print(f"  Lookup fallback used: {used_artist}")
    if used_title != title:
        print(f"  Lookup title used: {used_title}")
    save_lrc(lrc_file, lyrics, artist, title, album)
    if report_kind:
        kind = "synchronized lyrics" if _is_lrc_synced(lyrics) else "untimed lyrics"
        print(f"LYRICS_RESULT={kind}")
    print(f"✔ Saved lyrics: {lrc_file.name}")
    return ProcessResult.SAVED


def parse_extensions(raw: str) -> set[str]:
    return {
        "." + value.strip().lstrip(".").casefold()
        for value in raw.split(",")
        if value.strip()
    }


def collect_audio_files(
    scan_root: Path,
    extensions: set[str],
    recursive: bool,
) -> list[Path]:
    iterator = scan_root.rglob("*") if recursive else scan_root.iterdir()
    return sorted(
        path
        for path in iterator
        if path.is_file() and path.suffix.casefold() in extensions
    )


def print_directory_plan(
    groups: dict[Path, list[Path]],
    states: dict[Path, LrcState],
    force: bool,
    upgrade_plain: bool,
    synced_only: bool,
) -> int:
    selected_total = 0
    total = len(groups)
    for index, (directory, files) in enumerate(sorted(groups.items()), start=1):
        selected = sum(
            should_fetch_lrc(states[path], force, upgrade_plain, synced_only)
            for path in files
        )
        selected_total += selected
        if selected:
            print(
                f"[{index}/{total}] would fetch: {directory} "
                f"({selected} of {len(files)} selected)"
            )
        else:
            print(
                f"[{index}/{total}] skipped: {directory} "
                f"(0 of {len(files)} selected)"
            )
    return selected_total


def dry_run(
    audio_files: list[Path],
    scan_root: Path,
    recursive: bool,
    force: bool,
    upgrade_plain: bool,
    synced_only: bool,
) -> int:
    groups: dict[Path, list[Path]] = defaultdict(list)
    for path in audio_files:
        groups[path.parent].append(path)
    states = {path: lrc_state(lrc_path_for(path)) for path in audio_files}
    selected = print_directory_plan(
        groups,
        states,
        force,
        upgrade_plain,
        synced_only,
    )
    state_counts = Counter(states.values())

    tagged = 0
    fallback = 0
    unusable = 0
    for path in audio_files:
        if not should_fetch_lrc(
            states[path],
            force,
            upgrade_plain,
            synced_only,
        ):
            continue
        metadata = get_audio_metadata(path)
        _, artists, title, _, _ = track_identity(
            path,
            metadata,
            scan_root,
            recursive,
        )
        if metadata["title"] and metadata["artist"]:
            tagged += 1
        elif title and artists:
            fallback += 1
        else:
            unusable += 1

    print()
    print("Summary")
    print(f"  Audio files:             {len(audio_files)}")
    print(f"  Synchronized lyrics:     {state_counts[LrcState.SYNCED]}")
    print(f"  Untimed lyrics:          {state_counts[LrcState.UNTIMED]}")
    print(f"  Lyrics missing:          {state_counts[LrcState.MISSING]}")
    print(f"  Would fetch:             {selected}")
    print(f"  Tagged identities:       {tagged}")
    print(f"  Filename fallbacks:      {fallback}")
    print(f"  Unusable identities:     {unusable}")
    print()
    print("Preview only; providers were not contacted and no files were written.")
    return 1 if unusable else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch lyrics for an album or music library"
    )
    parser.add_argument(
        "directory",
        nargs="?",
        default=str(music_library_dir()),
        help=f"Album or music-library directory (default: {music_library_dir()})",
    )
    existing_group = parser.add_mutually_exclusive_group()
    existing_group.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="Overwrite existing .lrc files and refresh recent misses",
    )
    existing_group.add_argument(
        "--upgrade-plain",
        action="store_true",
        help="Replace existing untimed lyrics with synchronized lyrics only",
    )
    parser.add_argument(
        "--synced-only",
        action="store_true",
        help="Save only synchronized lyrics; ignore untimed results",
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Validate identities and report work without contacting providers",
    )
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="Process every supported audio file below the directory",
    )
    parser.add_argument(
        "--refresh-cache",
        action="store_true",
        help="Retry provider lookups cached as complete misses",
    )
    parser.add_argument(
        "--ext",
        default=DEFAULT_EXTENSIONS,
        help=f"Comma-separated extensions (default: {DEFAULT_EXTENSIONS})",
    )
    args = parser.parse_args()

    scan_root = Path(args.directory).expanduser()
    if not scan_root.is_dir():
        print(f"Error: '{scan_root}' is not a directory", file=sys.stderr)
        return 2

    extensions = parse_extensions(args.ext)
    if not extensions:
        parser.error("--ext produced no extensions")
    audio_files = collect_audio_files(scan_root, extensions, args.recursive)
    if not audio_files:
        print("No supported audio files found", file=sys.stderr)
        return 0

    mode = "music library" if args.recursive else "album"
    print(f"▶ Scanning {mode}: {scan_root}")
    print(f"  Audio files: {len(audio_files)}")
    print()

    if args.dry_run:
        return dry_run(
            audio_files,
            scan_root,
            args.recursive,
            args.force,
            args.upgrade_plain,
            args.synced_only,
        )

    results: Counter[ProcessResult] = Counter()
    current_directory = None
    for path in audio_files:
        if path.parent != current_directory:
            current_directory = path.parent
            print(f"\n[{current_directory}]")
        result = process_audio_file(
            path,
            scan_root,
            args.recursive,
            force=args.force,
            upgrade_plain=args.upgrade_plain,
            synced_only=args.synced_only,
            refresh_cache=args.force or args.refresh_cache,
        )
        results[result] += 1
        print()

    print("Summary")
    print(f"  Audio files:   {len(audio_files)}")
    print(f"  Saved:         {results[ProcessResult.SAVED]}")
    print(f"  Kept existing: {results[ProcessResult.KEPT]}")
    print(f"  Skipped:       {results[ProcessResult.SKIPPED]}")
    print(f"  Failed:        {results[ProcessResult.FAILED]}")
    return 1 if results[ProcessResult.FAILED] else 0


if __name__ == "__main__":
    raise SystemExit(main())
