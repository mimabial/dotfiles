#!/usr/bin/env python3
"""Run the shared lyrics pipeline for one audio file."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from fetch_album_lyrics import ProcessResult, process_audio_file
from lyrics_paths import lrc_path_for, music_library_dir


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio-file", type=Path, required=True)
    parser.add_argument("--lrc-file", type=Path)
    parser.add_argument("--scan-root", type=Path, default=music_library_dir())
    args = parser.parse_args()

    audio_file = args.audio_file.expanduser().resolve()
    if not audio_file.is_file():
        print(f"audio file not found: {audio_file}", file=sys.stderr)
        return 2

    try:
        result = process_audio_file(
            audio_file,
            args.scan_root.expanduser().resolve(),
            recursive=True,
            lrc_file=(args.lrc_file or lrc_path_for(audio_file)).expanduser(),
            report_kind=True,
        )
    except Exception as exc:  # noqa: BLE001 - command boundary reports runtime failure
        print(f"lyrics fetch failed: {exc}", file=sys.stderr)
        return 2
    return 1 if result is ProcessResult.FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
