from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import NamedTuple
from audio_tags import read_tags
from autotag_identity import album_context, derive_candidates, existing, first_artist_fallbacks, folder_hints, match_score, normalize_identity_tokens
from autotag_models import Unidentified
from autotag_cache import CACHE_MISS_TTL, CACHE_SUCCESS_TTL, CACHE_VERSION, ResolutionCache
from autotag_catalogs import EXACT_MATCH_SCORE, from_acoustid, from_deezer, from_itunes, from_musicbrainz


def resolution_cache_key(
    path: Path,
    candidates: list[tuple[str, str]],
    fallback_candidates: list[tuple[str, str]],
    args,
    has_acoustid_key: bool,
    album: str = "",
) -> str:
    file_stat = path.stat()
    payload = {
        "version": CACHE_VERSION,
        "path": str(path.absolute()),
        "size": file_stat.st_size,
        "mtime_ns": file_stat.st_mtime_ns,
        "candidates": candidates,
        "first_artist_fallbacks": fallback_candidates,
        "album": album,
        "acoustid": has_acoustid_key and not args.no_fingerprint,
        "min_score": args.min_score,
        "providers": args.provider_order,
        "fallback": args.fallback,
        "min_similarity": args.min_similarity,
    }
    if album and any(normalize_identity_tokens(album) == normalize_identity_tokens(title) for _, title in candidates):
        payload["single_reissue"] = True
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def cache_resolution(
    cache: ResolutionCache | None,
    path: Path,
    root: Path,
    tags,
    args,
    has_acoustid_key: bool,
    metadata: dict,
) -> None:
    if cache is None:
        return
    cached_metadata = {
        field: value
        for field, value in metadata.items()
        if not field.startswith("_")
    }
    candidates = derive_candidates(path, tags, root)
    album, _ = album_context(path, tags, root)
    cache.put(
        resolution_cache_key(
            path,
            candidates,
            first_artist_fallbacks(candidates),
            args,
            has_acoustid_key,
            album,
        ),
        {"identified": True, "metadata": cached_metadata},
        CACHE_SUCCESS_TTL,
    )


class SearchContext(NamedTuple):
    album: str
    single_release: bool
    tags: object
    failures: dict[str, list[str]]


class Resolver:
    """The settings, rate limiters, AcoustID key and cache are constant for every
    file in a run, so they are held here instead of being threaded through each
    resolution call."""

    def __init__(self, args, limiters: dict, acoustid_key: str = "",
                 cache: ResolutionCache | None = None, refresh_cache: bool = False):
        self.args = args
        self.limiters = limiters
        self.acoustid_key = acoustid_key
        self.cache = cache
        self.refresh_cache = refresh_cache

    def lookup(self, provider: str, artist: str, title: str, requested_album: str) -> dict:
        if provider == "itunes":
            return from_itunes(
                artist, title, self.limiters["itunes"], self.args.min_similarity, requested_album
            )
        if provider == "deezer":
            return from_deezer(
                artist, title, self.limiters["deezer"], self.args.min_similarity, requested_album
            )
        return from_musicbrainz(
            artist, title, self.limiters["musicbrainz"], album=requested_album
        )

    def _cache_result(self, cache_key: str, payload: dict, ttl) -> None:
        if self.cache is not None:
            self.cache.put(cache_key, payload, ttl)

    def _cache_identified_metadata(self, cache_key: str, metadata: dict) -> dict:
        self._cache_result(cache_key, {"identified": True, "metadata": metadata}, CACHE_SUCCESS_TTL)
        return metadata

    def _read_cached_resolution(self, cache_key: str) -> dict | None:
        """A cached miss raises, the same as a fresh one would."""
        if self.cache is None or self.refresh_cache:
            return None
        cached = self.cache.get(cache_key)
        if cached is None:
            return None
        if cached.get("identified"):
            return cached.get("metadata") or {}
        raise Unidentified(f"{cached.get('reason', 'no match')} [cached]")

    def _from_fingerprint(self, path: Path, cache_key: str, candidates: list,
                          fallback_candidates: list, album: str) -> dict | None:
        try:
            return self._cache_identified_metadata(
                cache_key,
                from_acoustid(
                    path,
                    self.acoustid_key,
                    self.limiters["acoustid"],
                    self.args.min_score,
                    candidates + (fallback_candidates if self.args.fallback else []),
                    album=album,
                ),
            )
        except Unidentified as exc:
            if not self.args.fallback:
                self._cache_result(
                    cache_key, {"identified": False, "reason": str(exc)}, CACHE_MISS_TTL
                )
                raise
            return None

    def _lookup_candidate(
        self, provider: str, artist: str, title: str, context: SearchContext
    ) -> dict | None:
        try:
            return self.lookup(provider, artist, title, context.album)
        except Unidentified as exc:
            if not context.single_release or not self.args.fallback:
                context.failures.setdefault(str(exc), []).append(provider)
                return None

        # A single whose album tag repeats its title can be delisted under that
        # album while the recording is still findable on its own; the local tags
        # stay authoritative for everything the relaxed search would widen.
        try:
            metadata = self.lookup(provider, artist, title, "")
        except Unidentified as relaxed_exc:
            context.failures.setdefault(str(relaxed_exc), []).append(provider)
            return None

        metadata.update(
            title=existing(context.tags, "title") or metadata.get("title", ""),
            artist=existing(context.tags, "artist") or metadata.get("artist", ""),
            album=context.album,
            date=existing(context.tags, "date"),
            tracknumber=existing(context.tags, "tracknumber") or "1/1",
            artwork_url="",
        )
        metadata.pop("musicbrainz_releasegroupid", None)
        return metadata

    def _search_tier(
        self, candidates: list, exact: bool, context: SearchContext
    ) -> dict | None:
        best = None
        best_score = 0.0
        for provider in self.args.provider_order:
            for artist, title in candidates:
                metadata = self._lookup_candidate(
                    provider, artist, title, context
                )
                if metadata is None:
                    continue
                if exact:
                    return metadata
                score = match_score(
                    metadata.get("artist", ""), metadata.get("title", ""), artist, title
                )
                if score > best_score:
                    best = metadata
                    best_score = score
                if score >= EXACT_MATCH_SCORE:
                    return metadata
            if not self.args.fallback:
                break
        return best

    @staticmethod
    def _failure_reason(candidate_tiers: list, failures: dict) -> str:
        tried = " | ".join(
            f"{artist} - {title}" if artist else title
            for candidate_tier in candidate_tiers
            for artist, title in candidate_tier
        )
        summary = "; ".join(
            f"{reason} ({', '.join(dict.fromkeys(providers))})"
            for reason, providers in failures.items()
        )
        return f"{summary} [tried: {tried}]"

    def resolve(self, path: Path, root: Path, tags=None) -> dict:
        if tags is None:
            tags = read_tags(path)
        candidates = derive_candidates(path, tags, root)
        fallback_candidates = first_artist_fallbacks(candidates)
        album, _ = album_context(path, tags, root)
        single_release = bool(
            album
            and not folder_hints(path, root)[1]
            and normalize_identity_tokens(album) == normalize_identity_tokens(existing(tags, "title"))
        )
        cache_key = (
            resolution_cache_key(
                path, candidates, fallback_candidates, self.args, bool(self.acoustid_key), album
            )
            if self.cache is not None
            else ""
        )

        cached = self._read_cached_resolution(cache_key)
        if cached is not None:
            return cached

        if self.acoustid_key and not self.args.no_fingerprint:
            metadata = self._from_fingerprint(
                path, cache_key, candidates, fallback_candidates, album
            )
            if metadata is not None:
                return metadata

        if not candidates:
            raise Unidentified("no title to search with")

        # Without an artist the gate cannot run and a generic title matches anything.
        candidates = [c for c in candidates if c[0]]
        if not candidates:
            raise Unidentified("no artist in filename, tags or parent folder")
        fallback_candidates = [c for c in fallback_candidates if c[0]]

        candidate_tiers = [candidates]
        if self.args.fallback and fallback_candidates:
            candidate_tiers.append(fallback_candidates)

        # Exhaust exact credits across every provider before relaxing to the first
        # artist. This keeps a broad iTunes result from beating an exact Deezer match.
        context = SearchContext(album, single_release, tags, {})
        for tier_index, candidate_tier in enumerate(candidate_tiers):
            metadata = self._search_tier(candidate_tier, tier_index == 0, context)
            if metadata is not None:
                return self._cache_identified_metadata(cache_key, metadata)

        reason = self._failure_reason(candidate_tiers, context.failures)
        self._cache_result(cache_key, {"identified": False, "reason": reason}, CACHE_MISS_TTL)
        raise Unidentified(reason)

