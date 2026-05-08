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
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lyrics_io import save_lrc  # noqa: E402
from lyrics_provider import fetch_lyrics  # noqa: E402


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

        save_lrc(args.lrc_file, lyrics, args.artist, args.title, args.album)
        return 0
    except Exception:
        return 2


if __name__ == "__main__":
    sys.exit(main())
