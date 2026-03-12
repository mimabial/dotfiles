#!/usr/bin/env python3
"""
Single-track lyrics fetch + write helper used by shell entrypoints.
Exit codes:
  0 = success
  1 = no lyrics found
  2 = internal/runtime error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lyrics_io import save_lrc  # noqa: E402
from lyrics_provider import fetch_lyrics  # noqa: E402


TIMESTAMP_RE = re.compile(r"^\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]")


def is_synced_lrc(lyrics: str) -> bool:
    has_non_zero_timestamp = False
    for raw_line in lyrics.splitlines():
        line = raw_line.strip()
        match = TIMESTAMP_RE.match(line)
        if not match:
            continue
        minutes = int(match.group(1))
        seconds = int(match.group(2))
        fraction = int((match.group(3) or "0").ljust(3, "0")[:3])
        if minutes != 0 or seconds != 0 or fraction != 0:
            has_non_zero_timestamp = True
            break
    return has_non_zero_timestamp


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch and save lyrics for a single track"
    )
    parser.add_argument("--artist", required=True, help="Lookup artist")
    parser.add_argument("--title", required=True, help="Track title")
    parser.add_argument("--album", default="", help="Album title")
    parser.add_argument("--lrc-file", required=True, help="Output .lrc path")
    parser.add_argument(
        "--expected-duration",
        type=float,
        default=None,
        help="Expected track duration in seconds",
    )
    parser.add_argument(
        "--require-synced",
        action="store_true",
        help="Return code 3 if only plain lyrics are available",
    )
    args = parser.parse_args()

    try:
        lyrics = fetch_lyrics(
            args.artist,
            args.title,
            args.album,
            expected_duration=args.expected_duration,
        )
        if not lyrics:
            return 1

        if args.require_synced and not is_synced_lrc(lyrics):
            return 3

        save_lrc(args.lrc_file, lyrics, args.artist, args.title, args.album)
        return 0
    except Exception:
        return 2


if __name__ == "__main__":
    sys.exit(main())
