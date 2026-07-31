#!/usr/bin/env python3
"""
Rename audio files after their own tags.

Previews by default; pass --apply to actually rename. Title cleaning and format
support are reused from autotag so the two agree on what a title is.

Exit codes:
  0 = every file renamed or already correct
  1 = at least one file was skipped
  2 = internal/runtime error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from mutagen import MutagenError

from autotag import (
    MIN_ALBUM_SIMILARITY,
    SUPPORTED,
    clean_title,
    drop_redundant_feat,
    existing,
    missing_credit_names,
    parse_filename,
    read_tags,
    similarity,
    split_leading_artist,
)
from media_move import (
    MoveError,
    apply_move_plan,
    build_move_plan,
    update_mpd,
)
from lyrics_paths import music_library_dir

DEFAULT_PATTERN = "{artist} - {title}"
DEFAULT_ALBUM_PATTERN = "{tracknumber}. {title}"
FIELDS = ("artist", "albumartist", "title", "album", "tracknumber", "date", "genre")


def sanitize(value: str) -> str:
    value = value.replace("/", "-")
    value = re.sub(r"[\x00-\x1f]", "", value)
    value = re.sub(r"\s{2,}", " ", value)
    return value.strip().rstrip(". ")


def fields_for(tags) -> dict:
    values = {name: sanitize(existing(tags, name)) for name in FIELDS}
    # Ripped-video tags repeat the artist in the title and keep the "(Music Video)"
    # suffix; without this the pattern renders both twice over.
    values["title"] = sanitize(
        drop_redundant_feat(
            clean_title(split_leading_artist(values["title"], values["artist"])),
            values["artist"],
        )
    )
    # "9/18" is a position plus a total; only the position belongs in a filename.
    track = existing(tags, "tracknumber").split("/", 1)[0].strip()
    values["tracknumber"] = f"{int(track):02d}" if track.isdigit() else track
    return values


def render(pattern: str, values: dict) -> str:
    try:
        return sanitize(pattern.format(**values))
    except KeyError as exc:
        raise SystemExit(f"unknown field {exc} in pattern; known: {', '.join(FIELDS)}")


def default_pattern_for(path: Path, tags) -> str:
    """Use compact numbered names only when the file is demonstrably in an album."""
    album = existing(tags, "album")
    raw_track = existing(tags, "tracknumber")
    if not album or not raw_track:
        return DEFAULT_PATTERN

    position, separator, total = raw_track.partition("/")
    position = position.strip()
    total = total.strip()
    numbered_album = (
        position.isdigit()
        and (
            int(position) > 1
            or (separator and total.isdigit() and int(total) > 1)
        )
    )
    album_folder = (
        similarity(path.parent.name, album) >= MIN_ALBUM_SIMILARITY
    )
    return DEFAULT_ALBUM_PATTERN if numbered_album or album_folder else DEFAULT_PATTERN


def credit_loss_for_rename(path: Path, values: dict) -> list[str]:
    """Return credits present in the current filename but absent from its target."""
    file_artist, file_title = parse_filename(path)
    if not file_artist or not file_title:
        return []
    return missing_credit_names(
        file_artist,
        file_title,
        values.get("artist", ""),
        values.get("title", ""),
    )


def collect(paths: list[str], wanted: set[str]) -> list[Path]:
    found: list[Path] = []
    for raw in paths:
        path = Path(raw).expanduser()
        if path.is_dir():
            found.extend(
                p for p in sorted(path.rglob("*"))
                if p.suffix.lower() in wanted and p.is_file()
            )
        elif path.suffix.lower() in wanted:
            found.append(path)
        else:
            print(f"skip (unsupported): {path}", file=sys.stderr)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rename audio files after their tags (previews unless --apply)"
    )
    parser.add_argument(
        "paths",
        nargs="*",
        metavar="PATH",
        help="Files or directories to rename (default: configured music library)",
    )
    parser.add_argument("--apply", action="store_true",
                        help="Perform the renames; without this nothing is written")
    parser.add_argument("--no-update", action="store_true",
                        help="Do not request an MPD database update after renaming")
    parser.add_argument(
        "--allow-credit-loss",
        action="store_true",
        help="Allow a rename that removes a credited artist from the filename",
    )
    parser.add_argument(
        "--pattern",
        default="",
        help=(
            f"Naming pattern override; defaults: {DEFAULT_ALBUM_PATTERN!r} for "
            f"album tracks, {DEFAULT_PATTERN!r} otherwise; fields: "
            f"{', '.join(f'{{{field}}}' for field in FIELDS)}"
        ),
    )
    parser.add_argument("--ext", default="",
                        help="Comma-separated extensions to include "
                             f"(default: {','.join(sorted(e[1:] for e in SUPPORTED))})")
    args = parser.parse_args()

    if args.ext:
        wanted = {"." + e.strip().lstrip(".").lower() for e in args.ext.split(",") if e.strip()}
        unknown = wanted - SUPPORTED
        if unknown:
            parser.error(f"unsupported extension(s): {', '.join(sorted(unknown))}")
    else:
        wanted = set(SUPPORTED)

    paths = args.paths or [str(music_library_dir())]
    files = collect(paths, wanted)
    if not files:
        print(f"no {'/'.join(sorted(wanted))} files found", file=sys.stderr)
        return 0

    renamed = unchanged = skipped = 0
    planned: set[Path] = set()

    for path in files:
        try:
            tags = read_tags(path)
            values = fields_for(tags)
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: unreadable: {exc}", file=sys.stderr)
            skipped += 1
            continue

        pattern = args.pattern or default_pattern_for(path, tags)
        missing = [f for f in re.findall(r"{(\w+)}", pattern) if not values.get(f)]
        if missing:
            print(f"?? {path.name}: no {', '.join(missing)} tag", file=sys.stderr)
            skipped += 1
            continue

        lost_credits = credit_loss_for_rename(path, values)
        if lost_credits and not args.allow_credit_loss:
            detail = f"would remove credit(s): {', '.join(lost_credits)}"
            print(f"!! {path.name}: {detail}", file=sys.stderr)
            skipped += 1
            continue

        target = path.with_name(render(pattern, values) + path.suffix.lower())
        if target == path:
            unchanged += 1
            continue
        if target in planned or (target.exists() and not target.samefile(path)):
            print(f"!! {path.name}: target exists: {target.name}", file=sys.stderr)
            skipped += 1
            continue

        try:
            move_plan = build_move_plan(path, target)
        except MoveError as exc:
            print(f"!! {path.name}: {exc}", file=sys.stderr)
            skipped += 1
            continue

        renamed += 1
        planned.add(target)
        if args.apply:
            try:
                apply_move_plan(move_plan)
            except (MoveError, OSError) as exc:
                print(f"!! {path.name}: rename failed: {exc}", file=sys.stderr)
                skipped += 1
                renamed -= 1
                continue
        verb = "RENAMED" if args.apply else "would rename"
        print(f"{verb}: {path.name}\n         -> {target.name}", flush=True)
        if move_plan.has_lyrics:
            lrc_verb = "RENAMED LRC" if args.apply else "would rename LRC"
            print(
                f"{lrc_verb}: {move_plan.lyrics_source.name}\n"
                f"             -> {move_plan.lyrics_target.name}",
                flush=True,
            )

    print(f"\n{renamed} to rename, {unchanged} already correct, {skipped} skipped"
          f"{'' if args.apply else '  (preview only; pass --apply)'}")
    if args.apply and renamed and not args.no_update:
        update_mpd()
    return 1 if skipped else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
