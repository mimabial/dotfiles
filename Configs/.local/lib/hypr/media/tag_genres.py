#!/usr/bin/env python3
"""
Interactively set the genre tag on every track in an album directory.

Tracks are presented in track-number order. An empty answer leaves the file
untouched; Ctrl-C stops without writing the current track.

Exit codes:
  0 = finished
  1 = at least one file could not be read or written
  2 = internal/runtime error
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from autotag import SUPPORTED, VORBIS, existing, read_tags  # noqa: E402

from mutagen import MutagenError  # noqa: E402


def track_key(path: Path) -> tuple:
    try:
        raw = existing(read_tags(path), "tracknumber").split("/")[0].strip()
    except (MutagenError, OSError):
        raw = ""
    return (int(raw) if raw.isdigit() else 9999, path.name.lower())


def set_genre(path: Path, genre: str) -> None:
    tags = read_tags(path)
    tags["GENRE" if path.suffix.lower() in VORBIS else "genre"] = genre
    tags.save()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Interactively set genre tags on each track in an album directory"
    )
    parser.add_argument("directory", help="Album directory")
    parser.add_argument("--genre", default="",
                        help="Apply this genre to every track without prompting")
    parser.add_argument("--recursive", action="store_true",
                        help="Descend into subdirectories")
    args = parser.parse_args()

    album = Path(args.directory).expanduser()
    if not album.is_dir():
        print(f"not a directory: {album}", file=sys.stderr)
        return 2

    walk = album.rglob("*") if args.recursive else album.iterdir()
    files = sorted(
        (p for p in walk if p.is_file() and p.suffix.lower() in SUPPORTED),
        key=track_key,
    )
    if not files:
        print(f"no audio files in {album}", file=sys.stderr)
        return 0

    failed = 0
    for path in files:
        try:
            tags = read_tags(path)
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: unreadable: {exc}", file=sys.stderr)
            failed += 1
            continue

        genre = args.genre
        if not genre:
            print(f"\n{path.name}")
            print(f"  Title: {existing(tags, 'title') or '-'}")
            print(f"  Track: {existing(tags, 'tracknumber') or '-'}")
            print(f"  Genre: {existing(tags, 'genre') or '-'}")
            try:
                genre = input("  Genre(s), comma-separated (blank to skip): ").strip()
            except EOFError:
                print()
                break
            if not genre:
                print("  skipped")
                continue

        try:
            set_genre(path, genre)
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: write failed: {exc}", file=sys.stderr)
            failed += 1
            continue
        print(f"  {path.name}: genre = {genre}" if args.genre else f"  set to: {genre}")

    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
