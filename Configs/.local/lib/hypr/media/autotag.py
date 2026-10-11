#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sqlite3
import sys
from collections import Counter
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import requests
from pyutils.xdg_base_dirs import xdg_cache_home, xdg_config_home
from mutagen import MutagenError
from audio_tags import SUPPORTED, SUPPORTED_LABEL, read_tags, selected_extensions
from autotag_identity import album_agrees, album_context, existing
from lyrics_paths import music_library_dir
from autotag_models import TrackTags, Unidentified
from autotag_cache import ResolutionCache
from autotag_catalogs import ACOUSTID_INTERVAL, DEEZER_INTERVAL, HTTP_SESSION, HTTP_TIMEOUT_S, ITUNES_INTERVAL, MUSICBRAINZ_INTERVAL, RateLimiter, acoustid_key, configure_persistent_cache
from autotag_youtube_credits import filename_credit_loss, recovered_youtube_artist
from autotag_tag_io import NON_TAG_FIELDS, embed_artwork, embedded_artwork, has_artwork, prepare_metadata, tidy_title, write_tags
from autotag_resolver import Resolver, cache_resolution


PROVIDERS = ("deezer", "itunes", "musicbrainz")


# iTunes leads as the only provider returning a genre; it costs ~5.4s to Deezer's ~0.3s.
DEFAULT_PROVIDER_ORDER = "itunes,deezer,musicbrainz"


# A lookup is only worth its round trip if one of these is still empty.
FILL_FIELDS = ("title", "artist", "album", "date", "tracknumber", "genre")


FIELDS = ("title", "artist", "album", "albumartist", "tracknumber", "date")


class AlbumArtworkGroup(NamedTuple):
    album: str
    paths: list[Path]
    roots: dict[Path, Path]
    metadata: dict[Path, dict]
    urls: list[str]


class ScannedAudioFile(NamedTuple):
    path: Path
    scan_root: Path


def collect_audio_files(paths: list[str], wanted_extensions: set[str]) -> list[ScannedAudioFile]:
    """Pairs each file with the scan root it came from, which folder_hints needs to
    know how deep the file sits."""
    library_root = music_library_dir()
    audio_files: list[ScannedAudioFile] = []
    for raw_path in paths:
        path = Path(raw_path).expanduser()
        if path.is_dir():
            scan_root = library_root if path.is_relative_to(library_root) else path
            audio_files.extend(
                ScannedAudioFile(candidate_path, scan_root)
                for candidate_path in sorted(path.rglob("*"))
                if candidate_path.suffix.lower() in wanted_extensions and candidate_path.is_file()
            )
        elif path.suffix.lower() in wanted_extensions:
            scan_root = library_root if path.is_relative_to(library_root) else path.parent
            audio_files.append(ScannedAudioFile(path, scan_root))
        elif path.suffix.lower() in SUPPORTED:
            print(f"skip (filtered by --ext): {path}", file=sys.stderr)
        else:
            print(f"skip (unsupported): {path}", file=sys.stderr)
    return audio_files


def restore_youtube_credit_tags(
    audio_files: list[ScannedAudioFile],
    dry_run: bool,
) -> int:
    """Repair only ARTIST tags, using filenames as the local loss signal."""
    restored = complete = failed = 0
    for audio_file in audio_files:
        path = audio_file.path
        try:
            tags = read_tags(path)
            lost_credits = filename_credit_loss(path, tags)
            if not lost_credits:
                complete += 1
                continue
            old_artist = existing(tags, "artist") or "(missing)"
            artist = recovered_youtube_artist(path, tags)
            if not dry_run:
                write_tags(path, {"artist": artist}, force=True, tags=tags)
        except Unidentified as exc:
            print(f"?? {path.name}: {exc}", file=sys.stderr)
            failed += 1
            continue
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: unreadable: {exc}", file=sys.stderr)
            failed += 1
            continue

        verb = "would restore" if dry_run else "restored"
        print(
            f"{verb} ARTIST: {path.name}\n"
            f"                {old_artist} -> {artist}",
            flush=True,
        )
        restored += 1

    restore_summary = "to restore" if dry_run else "restored"
    tag_word = "tag" if restored == 1 else "tags"
    print(
        f"\n{restored} ARTIST {tag_word} {restore_summary}, "
        f"{complete} already complete, {failed} failed"
        f"{'' if not dry_run else '  (dry run)'}"
    )
    return 1 if failed else 0


def add_lookup_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--no-fingerprint", action="store_true",
                        help="Skip AcoustID; match on existing tags or filename")
    parser.add_argument("--no-fallback", dest="fallback", action="store_false",
                        help="Fail instead of falling back to a MusicBrainz text search")
    parser.add_argument("--min-score", type=float, default=0.5,
                        help="Minimum AcoustID confidence (default: %(default)s)")
    parser.add_argument("--provider", default=DEFAULT_PROVIDER_ORDER,
                        help="Comma-separated providers to try in order "
                             f"(default: {DEFAULT_PROVIDER_ORDER}); "
                             f"any of: {', '.join(PROVIDERS)}")
    parser.add_argument("--fill", default=",".join(FILL_FIELDS),
                        help="Only look a file up when one of these tags is missing "
                             f"(default: {','.join(FILL_FIELDS)})")
    parser.add_argument("--min-similarity", type=float, default=0.60,
                        help="Minimum artist/title similarity (default: %(default)s)")


def add_artwork_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--no-artwork", dest="artwork", action="store_false",
                        help="Skip embedding cover art from the provider")
    parser.add_argument(
        "--replace-artwork",
        action="store_true",
        help="Replace existing artwork; tracks in one album share one catalog cover",
    )


def add_cache_options(parser: argparse.ArgumentParser) -> None:
    cache_group = parser.add_mutually_exclusive_group()
    cache_group.add_argument(
        "--no-cache",
        action="store_true",
        help="Do not read or write the persistent lookup cache",
    )
    cache_group.add_argument(
        "--refresh-cache",
        action="store_true",
        help="Ignore cached lookups and replace them with fresh results",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Look up track metadata and write it into .mp3/.opus/.flac files"
    )
    parser.add_argument(
        "paths",
        nargs="*",
        metavar="PATH",
        help="Files or directories to tag (default: configured music library)",
    )
    parser.add_argument("-n", "--dry-run", action="store_true",
                        help="Report what would change without writing")
    parser.add_argument("-f", "--force", action="store_true",
                        help="Overwrite existing tags instead of only filling gaps")
    parser.add_argument(
        "--allow-credit-loss",
        action="store_true",
        help="Allow --force to replace a richer local artist credit with a narrower one",
    )
    parser.add_argument(
        "--restore-youtube-credits",
        action="store_true",
        help="Only repair ARTIST tags from verified YouTube purl metadata",
    )
    add_lookup_options(parser)
    add_artwork_options(parser)
    add_cache_options(parser)
    parser.add_argument("--ext", default="",
                        help="Comma-separated extensions to include "
                             f"(default: {SUPPORTED_LABEL})")
    return parser


def replacing_artwork(args) -> bool:
    """--force implies --replace-artwork: a forced retag rewrites the very credits
    the existing cover was chosen for."""
    return args.force or args.replace_artwork


def parse_args(argv=None) -> tuple[argparse.Namespace, set[str]]:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.provider == "auto":
        args.provider = DEFAULT_PROVIDER_ORDER
    args.provider_order = [p.strip().lower() for p in args.provider.split(",") if p.strip()]
    unknown = [p for p in args.provider_order if p not in PROVIDERS]
    if unknown or not args.provider_order:
        parser.error(f"unknown provider(s): {', '.join(unknown) or '(none given)'}")

    args.fill_fields = [f.strip().lower() for f in args.fill.split(",") if f.strip()]
    unknown = [f for f in args.fill_fields if f not in FILL_FIELDS]
    if unknown:
        parser.error(f"unknown --fill field(s): {', '.join(unknown)}")

    try:
        wanted = selected_extensions(args.ext)
    except ValueError as error:
        parser.error(str(error))

    return args, wanted


def open_lookup_cache(args) -> ResolutionCache | None:
    if args.no_cache:
        return None
    try:
        return ResolutionCache(xdg_cache_home() / "hypr" / "autotag.sqlite3")
    except (OSError, sqlite3.Error) as exc:
        print(f"lookup cache unavailable: {exc}", file=sys.stderr)
        return None


def report_dry_run(path: Path, tags, meta: dict, args, in_album_group: bool) -> None:
    changes = {
        f: v for f, v in meta.items()
        if f not in NON_TAG_FIELDS and v and (args.force or not existing(tags, f))
    }
    if (
        not in_album_group
        and args.artwork
        and meta.get("artwork_url")
        and (replacing_artwork(args) or not has_artwork(path, tags))
    ):
        changes["artwork"] = meta["artwork_url"].rsplit("/", 1)[-1]
    summary = ", ".join(f"{f}={v!r}" for f, v in changes.items()) or "nothing to change"
    print(f"-- {path.name}: {summary}", flush=True)


def embed_track_artwork(path: Path, meta: dict, written: dict) -> None:
    image = HTTP_SESSION.get(meta["artwork_url"], timeout=HTTP_TIMEOUT_S)
    image.raise_for_status()
    if embedded_artwork(path) != image.content:
        embed_artwork(path, image.content)
        written["artwork"] = f"{len(image.content) // 1024}KB"


def apply_album_artwork(group: AlbumArtworkGroup, resolver: Resolver) -> int:
    args = resolver.args
    artwork_url = Counter(group.urls).most_common(1)[0][0]

    if args.dry_run:
        name = artwork_url.rsplit("/", 1)[-1]
        print(f"-- {group.album}: artwork={name!r} for {len(group.paths)} file(s)", flush=True)
        return 0

    try:
        image = HTTP_SESSION.get(artwork_url, timeout=HTTP_TIMEOUT_S)
        image.raise_for_status()
    except requests.RequestException as exc:
        print(f"!! {group.album}: artwork download failed: {exc}", file=sys.stderr)
        return 1

    failed = 0
    updated = 0
    unchanged = 0
    for path in group.paths:
        try:
            if embedded_artwork(path) == image.content:
                unchanged += 1
            else:
                embed_artwork(path, image.content)
                updated += 1
            metadata = group.metadata.get(path)
            if metadata is not None:
                cache_resolution(
                    resolver.cache, path, group.roots[path], read_tags(path), args,
                    bool(resolver.acoustid_key), metadata,
                )
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: artwork failed: {exc}", file=sys.stderr)
            failed += 1
    print(
        f"ART {group.album}: one cover -> "
        f"{updated} updated, {unchanged} already correct",
        flush=True,
    )
    return failed


def join_album_artwork_group(
    album_artwork_groups: dict[tuple, AlbumArtworkGroup],
    album_key: tuple,
    album: str,
    path: Path,
    root: Path,
) -> AlbumArtworkGroup:
    group = album_artwork_groups.setdefault(album_key, AlbumArtworkGroup(album, [], {}, {}, []))
    group.paths.append(path)
    group.roots[path] = root
    return group


def report_written(path: Path, meta: TrackTags, written) -> None:
    identity = f"{meta.get('artist') or '?'} - {meta.get('title') or '?'}"
    if written:
        print(f"OK {path.name}: {identity} [{', '.join(sorted(written))}]", flush=True)
    else:
        print(f"== {path.name}: {identity} (already tagged)", flush=True)


def resolve_track_metadata(path: Path, root: Path, tags, resolver: Resolver) -> dict:
    args = resolver.args
    meta = prepare_metadata(
        tags, resolver.resolve(path, root, tags), args.force, allow_credit_loss=args.allow_credit_loss, path=path
    )
    if meta.get("_preserved_credits"):
        print(f".. {path.name}: preserved local credit(s): {meta['_preserved_credits']}", flush=True)
    return meta


def tag_file(
    path: Path,
    root: Path,
    resolver: Resolver,
    album_artwork_groups: dict[tuple, AlbumArtworkGroup],
) -> str:
    args = resolver.args
    replace_artwork = replacing_artwork(args)
    tags = read_tags(path)
    album, album_key = album_context(path, tags, root)
    artwork_group = (
        join_album_artwork_group(album_artwork_groups, album_key, album, path, root)
        if args.artwork and replace_artwork and album_key
        else None
    )

    tidied = tidy_title(path, args.dry_run, tags)
    if tidied:
        verb = "would drop" if args.dry_run else "dropped"
        print(f".. {path.name}: {verb} duplicated credit -> {tidied!r}", flush=True)

    if not replace_artwork and args.fill_fields and all(
        existing(tags, field) for field in args.fill_fields
    ):
        return "skipped"

    meta = resolve_track_metadata(path, root, tags, resolver)
    if artwork_group is not None:
        artwork_group.metadata[path] = meta
        if meta.get("artwork_url") and album_agrees(meta.get("album", ""), album):
            artwork_group.urls.append(meta["artwork_url"])

    if args.dry_run:
        report_dry_run(path, tags, meta, args, artwork_group is not None)
        return "reported"

    written = write_tags(path, meta, args.force, tags)

    if (
        artwork_group is None
        and args.artwork
        and meta.get("artwork_url")
        and (replace_artwork or not has_artwork(path, tags))
    ):
        embed_track_artwork(path, meta, written)

    # Tag/artwork writes change the file signature used by the cache.
    # Alias the same result under the new signature for the next scan.
    if resolver.cache is not None and written:
        cache_resolution(resolver.cache, path, root, tags, args, bool(resolver.acoustid_key), meta)

    report_written(path, meta, written)
    return "written"


def make_resolver(args, lookup_key: str, cache) -> Resolver:
    return Resolver(
        args,
        {
            "acoustid": RateLimiter(ACOUSTID_INTERVAL),
            "musicbrainz": RateLimiter(MUSICBRAINZ_INTERVAL),
            "itunes": RateLimiter(ITUNES_INTERVAL),
            "deezer": RateLimiter(DEEZER_INTERVAL),
        },
        lookup_key,
        cache,
        args.refresh_cache,
    )


def tag_files(
    audio_files: list[ScannedAudioFile],
    resolver: Resolver,
    album_artwork_groups: dict[tuple, AlbumArtworkGroup],
) -> tuple[int, int]:
    failed = complete = 0
    for audio_file in audio_files:
        path = audio_file.path
        try:
            if tag_file(path, audio_file.scan_root, resolver, album_artwork_groups) == "skipped":
                complete += 1
        except Unidentified as exc:
            print(f"?? {path.name}: {exc}", file=sys.stderr)
            failed += 1
        except requests.RequestException as exc:
            print(f"!! {path.name}: lookup failed: {exc}", file=sys.stderr)
            failed += 1
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: unreadable: {exc}", file=sys.stderr)
            failed += 1
    return failed, complete


def close_lookup_cache(cache) -> None:
    if cache is None:
        return
    if cache.hits:
        print(f"reused {cache.hits} cached lookup(s)", file=sys.stderr)
    configure_persistent_cache(None)
    cache.close()


def main() -> int:
    args, wanted = parse_args()

    paths = args.paths or [str(music_library_dir())]
    audio_files = collect_audio_files(paths, wanted)
    if not audio_files:
        print(f"no {'/'.join(sorted(wanted))} files found", file=sys.stderr)
        return 0

    if args.restore_youtube_credits:
        return restore_youtube_credit_tags(audio_files, args.dry_run)

    key = acoustid_key()
    if not key and not args.no_fingerprint:
        print(
            "no AcoustID key (set ACOUSTID_API_KEY or "
            f"{xdg_config_home()}/acoustid/api.token); using text search",
            file=sys.stderr,
        )

    cache = open_lookup_cache(args)
    configure_persistent_cache(cache)
    resolver = make_resolver(args, "" if replacing_artwork(args) else key, cache)
    album_artwork_groups: dict[tuple, AlbumArtworkGroup] = {}
    failed, complete = tag_files(audio_files, resolver, album_artwork_groups)

    if args.artwork and replacing_artwork(args):
        for group in album_artwork_groups.values():
            if group.urls:
                failed += apply_album_artwork(group, resolver)

    if complete:
        print(f"\nskipped {complete} file(s) already carrying every --fill tag", file=sys.stderr)
    close_lookup_cache(cache)
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)

