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

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from autotag import (  # noqa: E402
    SUPPORTED,
    clean_title,
    existing,
    normalize,
    read_tags,
    split_leading_artist,
)

from mutagen import MutagenError  # noqa: E402

DEFAULT_PATTERN = "{artist} - {title}"
FIELDS = ("artist", "albumartist", "title", "album", "tracknumber", "date", "genre")


def sanitize(value: str) -> str:
    value = value.replace("/", "-")
    value = re.sub(r"[\x00-\x1f]", "", value)
    value = re.sub(r"\s{2,}", " ", value)
    return value.strip().rstrip(". ")


FEAT = re.compile(
    r"\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s+(?P<who>[^)\]]*)[\)\]]", re.I
)


def drop_redundant_feat(title: str, artist: str) -> str:
    """YouTube Music credits featured artists in the artist field and again inside
    the official title. Drop the second copy only when the first already names
    them: on a plain upload the feat is the only record of the collaborator."""
    if not artist:
        return title

    known = set(normalize(artist))

    def prune(match: re.Match) -> str:
        who = set(normalize(match.group("who")))
        return "" if who and who <= known else match.group(0)

    return re.sub(r"\s{2,}", " ", FEAT.sub(prune, title)).strip()


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
    track = values["tracknumber"].split("/")[0].strip()
    values["tracknumber"] = f"{int(track):02d}" if track.isdigit() else track
    return values


def render(pattern: str, values: dict) -> str:
    try:
        return sanitize(pattern.format(**values))
    except KeyError as exc:
        raise SystemExit(f"unknown field {exc} in pattern; known: {', '.join(FIELDS)}")


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
    parser.add_argument("paths", nargs="+", help="Files or directories to rename")
    parser.add_argument("--apply", action="store_true",
                        help="Perform the renames; without this nothing is written")
    parser.add_argument("--pattern", default=DEFAULT_PATTERN,
                        help=f"Naming pattern (default: {DEFAULT_PATTERN!r}); "
                             f"fields: {', '.join('{%s}' % f for f in FIELDS)}")
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

    files = collect(args.paths, wanted)
    if not files:
        print(f"no {'/'.join(sorted(wanted))} files found", file=sys.stderr)
        return 0

    renamed = unchanged = skipped = 0
    planned: set[Path] = set()

    for path in files:
        try:
            values = fields_for(read_tags(path))
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: unreadable: {exc}", file=sys.stderr)
            skipped += 1
            continue

        missing = [f for f in re.findall(r"{(\w+)}", args.pattern) if not values.get(f)]
        if missing:
            print(f"?? {path.name}: no {', '.join(missing)} tag", file=sys.stderr)
            skipped += 1
            continue

        target = path.with_name(render(args.pattern, values) + path.suffix.lower())
        if target == path:
            unchanged += 1
            continue
        if target in planned or (target.exists() and not target.samefile(path)):
            print(f"!! {path.name}: target exists: {target.name}", file=sys.stderr)
            skipped += 1
            continue

        planned.add(target)
        renamed += 1
        if args.apply:
            try:
                path.rename(target)
            except OSError as exc:
                print(f"!! {path.name}: rename failed: {exc}", file=sys.stderr)
                skipped += 1
                renamed -= 1
                continue
        verb = "RENAMED" if args.apply else "would rename"
        print(f"{verb}: {path.name}\n         -> {target.name}", flush=True)

    print(f"\n{renamed} to rename, {unchanged} already correct, {skipped} skipped"
          f"{'' if args.apply else '  (preview only; pass --apply)'}")
    return 1 if skipped else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
