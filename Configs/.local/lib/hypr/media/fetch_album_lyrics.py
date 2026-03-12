#!/usr/bin/env python3
"""
Album lyrics fetcher for rmpc.
Uses shared provider logic from lyrics_provider.py.
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lyrics_provider import fetch_lyrics  # noqa: E402
from lyrics_io import save_lrc  # noqa: E402

GENERIC_ALBUM_ARTISTS = {
    "various artists",
    "various artist",
    "various",
    "va",
    "soundtrack",
    "original soundtrack",
    "original motion picture soundtrack",
}


def is_generic_album_artist(value: str) -> bool:
    return value.strip().lower() in GENERIC_ALBUM_ARTISTS


def build_artist_candidates(track_artist: str, album_artist: str, fallback: str) -> List[str]:
    candidates: List[str] = []

    def add(value: str) -> None:
        name = (value or "").strip()
        if not name or name in candidates:
            return
        candidates.append(name)

    if album_artist and not is_generic_album_artist(album_artist):
        add(album_artist)
    add(track_artist)
    add(fallback)
    return candidates


def get_audio_metadata(file_path: str) -> Dict[str, Any]:
    """Extract metadata from audio file using ffprobe."""
    import subprocess

    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "quiet",
                "-show_entries",
                "format=duration:format_tags=title,artist,album,album_artist,albumartist",
                "-of",
                "json",
                file_path,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(result.stdout)
        tags = data.get("format", {}).get("tags", {})

        return {
            "title": tags.get("TITLE") or tags.get("title") or "",
            "artist": tags.get("ARTIST") or tags.get("artist") or "",
            "album_artist": tags.get("ALBUMARTIST")
            or tags.get("album_artist")
            or tags.get("albumartist")
            or "",
            "album": tags.get("ALBUM") or tags.get("album") or "",
            "duration": float(data.get("format", {}).get("duration", 0) or 0),
        }
    except Exception as e:
        print(f"Warning: Could not extract metadata: {e}", file=sys.stderr)
        return {
            "title": "",
            "artist": "",
            "album_artist": "",
            "album": "",
            "duration": 0.0,
        }


def process_audio_file(
    file_path: Path, artist_dir: str, album_dir: str, force: bool = False
) -> bool:
    """Process a single audio file and fetch lyrics."""
    lrc_file = file_path.with_suffix(".lrc")

    if lrc_file.exists() and not force:
        print(f"– Skipping {file_path.name} (already have .lrc)")
        return True

    metadata = get_audio_metadata(str(file_path))

    track_artist = metadata.get("artist") or ""
    album_artist = metadata.get("album_artist") or ""
    artist_candidates = build_artist_candidates(track_artist, album_artist, artist_dir)
    save_artist = track_artist or (
        album_artist if album_artist and not is_generic_album_artist(album_artist) else ""
    )
    if not save_artist:
        save_artist = artist_dir

    album = metadata["album"] or album_dir
    title = metadata["title"]
    expected_duration = float(metadata.get("duration") or 0.0)

    if not title:
        title = file_path.stem
        title = re.sub(r"^[0-9]{1,3}[. -]+", "", title)

    print(f"→ Processing: {file_path.name}")
    print(f"  Title: {title}")
    print(f"  Artist: {save_artist}")
    print(f"  Album: {album}")

    lyrics = None
    used_artist = ""
    for candidate_artist in artist_candidates:
        lyrics = fetch_lyrics(
            candidate_artist, title, album, expected_duration=expected_duration
        )
        if lyrics:
            used_artist = candidate_artist
            break

    if not lyrics:
        print(f'✗ No lyrics found for: "{title}"')
        return False

    if used_artist != save_artist:
        print(f"  Lookup fallback used: {used_artist}")

    save_lrc(lrc_file, lyrics, save_artist, title, album)

    print(f"✔ Saved lyrics: {lrc_file.name}")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch synced lyrics for audio files using multiple sources"
    )
    parser.add_argument("album_dir", help="Path to album directory")
    parser.add_argument(
        "-f", "--force", action="store_true", help="Overwrite existing .lrc files"
    )

    args = parser.parse_args()

    album_path = Path(args.album_dir)
    if not album_path.is_dir():
        print(f"Error: '{args.album_dir}' is not a directory", file=sys.stderr)
        sys.exit(1)

    artist = album_path.parent.name
    album = album_path.name

    print(f"▶ Fetching lyrics for all audio files in: {album_path}")
    print(f"  Artist: {artist}")
    print(f"  Album:  {album}")
    print()

    audio_extensions = [".mp3", ".flac", ".m4a", ".ogg", ".opus"]
    audio_files = []
    for ext in audio_extensions:
        audio_files.extend(album_path.glob(f"*{ext}"))

    audio_files.sort()

    if not audio_files:
        print("No audio files found")
        sys.exit(1)

    success_count = 0
    for audio_file in audio_files:
        if process_audio_file(audio_file, artist, album, args.force):
            success_count += 1
        print()

    total_files = len(audio_files)
    print(f"Done. Successfully fetched lyrics for {success_count}/{total_files} files.")

    if success_count == total_files:
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()
