#!/usr/bin/env python3
"""Lyrics provider orchestration and candidate selection."""

from __future__ import annotations

import sys
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from typing import List, Optional, Tuple

from lyrics_provider_common import (
    ProviderFetcher,
    ProviderResult,
    _env_bool,
    _extract_lrc_tag,
    _is_placeholder_artist,
    _similarity,
    _split_artists,
)
from lyrics_provider_fetchers import (
    fetch_lyrics_chartlyrics,
    fetch_lyrics_genius,
    fetch_lyrics_lyricsfreek,
    fetch_lyrics_lyricsovh,
    fetch_lyrics_lrclib,
    fetch_lyrics_simpmusic,
    fetch_lyrics_youtube,
)

SONG_MATCH_THRESHOLD = 0.72
ARTIST_MATCH_THRESHOLD = 0.68

def _is_candidate_valid(requested_artist: str, requested_title: str, result: ProviderResult) -> bool:
    lyrics = str(result.get("lyrics") or "")
    result_artist = str(result.get("artist") or _extract_lrc_tag(lyrics, "ar") or "")
    result_title = str(result.get("title") or _extract_lrc_tag(lyrics, "ti") or "")

    if not result_title:
        result_title = requested_title
    if not result_artist:
        result_artist = requested_artist

    title_score = _similarity(requested_title, result_title)
    if title_score < SONG_MATCH_THRESHOLD:
        print(
            f"  [validate] Rejected by title score {title_score:.2f}: '{result_title}'",
            file=sys.stderr,
        )
        return False

    requested_artists = _split_artists(requested_artist)
    result_artists = _split_artists(result_artist)
    if _is_placeholder_artist(requested_artist):
        return True
    if not requested_artists or not result_artists:
        return True

    result_artist_full = " ".join(result_artists)
    artist_ok = False
    for req_artist in requested_artists:
        if any(_similarity(req_artist, got_artist) >= ARTIST_MATCH_THRESHOLD for got_artist in result_artists):
            artist_ok = True
            break
        if len(req_artist) > 3 and req_artist in result_artist_full:
            artist_ok = True
            break

    if not artist_ok:
        print(
            f"  [validate] Rejected by artist mismatch: requested='{requested_artist}' got='{result_artist}'",
            file=sys.stderr,
        )
        return False

    return True


def _fetch_candidate(
    source_name: str,
    fetcher: ProviderFetcher,
    artist: str,
    title: str,
    album: str,
) -> Optional[ProviderResult]:
    result = fetcher(artist, title, album)
    if not result:
        return None
    if not _is_candidate_valid(artist, title, result):
        print(f"  [{source_name}] Rejected by validator", file=sys.stderr)
        return None
    return result


def _choose_plain_candidate(
    plain_candidates: List[ProviderResult],
    ordered_sources: List[Tuple[str, ProviderFetcher]],
) -> Optional[ProviderResult]:
    if not plain_candidates:
        return None

    source_priority = {name: idx for idx, (name, _) in enumerate(ordered_sources)}
    sorted_candidates = sorted(
        plain_candidates,
        key=lambda item: source_priority.get(str(item.get("source", "")), 999),
    )
    return sorted_candidates[0]


def _fetch_sequential(
    providers: List[Tuple[str, ProviderFetcher]],
    artist: str,
    title: str,
    album: str,
    require_synced: bool,
) -> Tuple[Optional[ProviderResult], List[ProviderResult]]:
    plain_candidates: List[ProviderResult] = []
    for source_name, fetcher in providers:
        result = _fetch_candidate(source_name, fetcher, artist, title, album)
        if not result:
            continue
        if require_synced and not bool(result.get("synced")):
            plain_candidates.append(result)
            print(
                f"  [{source_name}] Plain lyrics available, continuing synced search",
                file=sys.stderr,
            )
            continue
        return result, plain_candidates
    return None, plain_candidates


def _fetch_parallel(
    providers: List[Tuple[str, ProviderFetcher]],
    artist: str,
    title: str,
    album: str,
    require_synced: bool,
) -> Tuple[Optional[ProviderResult], List[ProviderResult]]:
    if not providers:
        return None, []

    plain_candidates: List[ProviderResult] = []
    max_workers = min(len(providers), 4)
    executor = ThreadPoolExecutor(max_workers=max_workers)
    executor_shutdown = False
    try:
        pending = {
            executor.submit(_fetch_candidate, source_name, fetcher, artist, title, album): source_name
            for source_name, fetcher in providers
        }

        while pending:
            done, _ = wait(list(pending.keys()), return_when=FIRST_COMPLETED)
            for future in done:
                source_name = pending.pop(future)
                try:
                    result = future.result()
                except Exception as e:
                    print(f"  [{source_name}] Error in worker: {e}", file=sys.stderr)
                    continue

                if not result:
                    continue

                if require_synced and not bool(result.get("synced")):
                    plain_candidates.append(result)
                    print(
                        f"  [{source_name}] Plain lyrics available, continuing synced search",
                        file=sys.stderr,
                    )
                    continue

                for pending_future in pending:
                    pending_future.cancel()
                try:
                    executor.shutdown(wait=False, cancel_futures=True)
                except TypeError:
                    executor.shutdown(wait=False)
                executor_shutdown = True
                return result, plain_candidates
    finally:
        if not executor_shutdown:
            executor.shutdown(wait=True)

    return None, plain_candidates


def fetch_lyrics(
    artist: str,
    title: str,
    album: str = "",
    fast_mode: bool = False,
    expected_duration: Optional[float] = None,
) -> Optional[str]:
    parallel_mode = fast_mode or _env_bool("LYRICS_FAST_MODE", True)
    prefer_synced = _env_bool("LYRICS_PREFER_SYNCED", True)

    synced_providers: List[Tuple[str, ProviderFetcher]] = [
        (
            "lrclib",
            lambda a, t, alb: fetch_lyrics_lrclib(a, t, alb),
        ),
        (
            "simpmusic",
            lambda a, t, alb: fetch_lyrics_simpmusic(
                a, t, alb, expected_duration=expected_duration
            ),
        ),
        (
            "ytmusic",
            lambda a, t, alb: fetch_lyrics_youtube(a, t),
        ),
    ]
    plain_providers: List[Tuple[str, ProviderFetcher]] = [
        (
            "genius",
            lambda a, t, alb: fetch_lyrics_genius(a, t),
        ),
        (
            "lyrics.ovh",
            lambda a, t, alb: fetch_lyrics_lyricsovh(a, t),
        ),
        (
            "chartlyrics",
            lambda a, t, alb: fetch_lyrics_chartlyrics(a, t),
        ),
        (
            "lyricsfreek",
            lambda a, t, alb: fetch_lyrics_lyricsfreek(a, t),
        ),
    ]
    provider_order = synced_providers + plain_providers

    fetch_fn = _fetch_parallel if parallel_mode else _fetch_sequential
    mode_name = "parallel" if parallel_mode else "sequential"
    print(
        f"  [multi] mode={mode_name} prefer_synced={str(prefer_synced).lower()}",
        file=sys.stderr,
    )

    if prefer_synced:
        synced_result, plain_candidates = fetch_fn(
            synced_providers, artist, title, album, require_synced=True
        )
        if synced_result:
            return str(synced_result["lyrics"])

        plain_result = _choose_plain_candidate(plain_candidates, provider_order)
        if plain_result:
            print(
                f"  [{plain_result['source']}] Using plain lyrics fallback after synced search",
                file=sys.stderr,
            )
            return str(plain_result["lyrics"])

        plain_direct_result, _ = fetch_fn(
            plain_providers, artist, title, album, require_synced=False
        )
        if plain_direct_result:
            return str(plain_direct_result["lyrics"])

        return None

    first_result, _ = fetch_fn(
        provider_order, artist, title, album, require_synced=False
    )
    if first_result:
        return str(first_result["lyrics"])

    return None
