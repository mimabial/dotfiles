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

from lyrics_io import save_lrc
from lyrics_provider import fetch_lyrics


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch and save lyrics for a single track"
    )
    parser.add_argument("--artist", required=True, help="Lookup artist")
    parser.add_argument("--title", required=True, help="Track title")
    parser.add_argument("--album", default="", help="Album title")
    parser.add_argument(
        "--lrc-artist",
        help="Canonical artist written to the LRC header (defaults to lookup artist)",
    )
    parser.add_argument(
        "--lrc-title",
        help="Canonical title written to the LRC header (defaults to lookup title)",
    )
    parser.add_argument(
        "--lrc-album",
        help="Canonical album written to the LRC header (defaults to lookup album)",
    )
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

        save_lrc(
            args.lrc_file,
            lyrics,
            args.lrc_artist or args.artist,
            args.lrc_title or args.title,
            args.album if args.lrc_album is None else args.lrc_album,
        )
        return 0
    except Exception as exc:  # noqa: BLE001 - command boundary reports runtime failure
        print(f"lyrics fetch failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
