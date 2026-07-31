#!/usr/bin/env python3
"""User-facing command for moving a music file or directory with its lyrics."""

from __future__ import annotations

import argparse
import sys

from media_move import MoveError, MovePlan, apply_move_plan, build_move_plan, update_mpd
from lyrics_paths import music_library_dir


def print_plan(plan: MovePlan, verb: str) -> None:
    print(f"{verb}: {plan.source}\n      -> {plan.target}")
    if plan.has_lyrics:
        print(f"{verb} lyrics: {plan.lyrics_source}\n             -> {plan.lyrics_target}")
    else:
        print("Lyrics: none to move")


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="hyprshell media/music_move",
        description="Move a music file or directory with its mirrored lyrics",
    )
    parser.add_argument(
        "source",
        help=f"Existing file or directory below {music_library_dir()}",
    )
    parser.add_argument("destination", help="New path or existing destination directory")
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Print the planned move without changing files",
    )
    parser.add_argument(
        "--no-update",
        action="store_true",
        help="Do not request an MPD database update after moving",
    )
    args = parser.parse_args()

    try:
        plan = build_move_plan(
            args.source,
            args.destination,
            require_music_root=True,
        )
    except MoveError as exc:
        print(f"{parser.prog}: {exc}", file=sys.stderr)
        return 1

    if args.dry_run:
        print_plan(plan, "Would move")
        return 0

    try:
        apply_move_plan(plan)
    except (MoveError, OSError) as exc:
        print(f"{parser.prog}: move failed: {exc}", file=sys.stderr)
        return 1

    print_plan(plan, "Moved")
    if not args.no_update:
        update_mpd()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
