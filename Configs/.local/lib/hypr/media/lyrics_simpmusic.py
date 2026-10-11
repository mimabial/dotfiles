from __future__ import annotations

import re
import sys
import threading
import time
from http import HTTPStatus

from lyrics_cache import lyrics_miss_cache
from lyrics_text import ProviderResult, build_result, lrc_header, normalize_text, text_similarity, to_lrc_from_plain
from lyrics_http import DEFAULT_TIMEOUT, response_ok, http_get


SIMPMUSIC_API_BASE = "https://api-lyrics.simpmusic.org/v1"


_SIMPMUSIC_COOLDOWN_KEY = "simpmusic"


SIMPMUSIC_COOLDOWN_TTL = 60 * 60


_SIMPMUSIC_COOLDOWN_LOCK = threading.Lock()


_SIMPMUSIC_COOLDOWN_UNTIL = 0.0


_SIMPMUSIC_NOTICE_UNTIL = 0.0


SIMPMUSIC_CANDIDATE_LIMIT = 8


SIMPMUSIC_LEAD_LINES = 3


SIMPMUSIC_MIN_MATCH_SCORE = 0.35


# Prefer strong title/artist matches and reward lyrics previews that actually
# contain the requested title phrase/tokens, especially near the start.
# Duration is intentionally excluded because SimpMusic duration metadata is
# inconsistent for duplicate title/artist candidates.
SIMPMUSIC_SCORE_WEIGHTS = {
    "title": 0.45,
    "artist": 0.25,
    "album": 0.15,
    "title_in_lyrics": 0.05,
    "title_in_lead": 0.10,
}


def _simpmusic_title(candidate: dict) -> str:
    return str(candidate.get("songTitle") or candidate.get("title") or candidate.get("name") or "")


def _title_coverage(requested_title: str, token_patterns: list[re.Pattern], text: str) -> float:
    if not (requested_title and text):
        return 0.0
    if requested_title in text:
        return 1.0
    if not token_patterns:
        return 0.0
    return sum(1 for pattern in token_patterns if pattern.search(text)) / len(token_patterns)


def _pick_best_simpmusic_search_result(
    results: list[dict],
    artist: str,
    title: str,
    album: str = "",
    expected_duration: float | None = None,
) -> dict | None:
    best_result = None
    best_score = -1.0

    requested_title = normalize_text(title)
    requested_album = normalize_text(album)
    title_tokens = [token for token in requested_title.split() if len(token) > 1]
    title_token_patterns = [re.compile(rf"\b{re.escape(token)}\b") for token in title_tokens]

    for candidate in results[:SIMPMUSIC_CANDIDATE_LIMIT]:
        if not isinstance(candidate, dict):
            continue

        cand_artist = str(candidate.get("artistName") or candidate.get("artist") or "")
        cand_album = str(candidate.get("albumName") or candidate.get("album") or "")
        lyrics_preview = str(
            candidate.get("plainLyric")
            or candidate.get("plainLyrics")
            or candidate.get("lyrics")
            or ""
        )
        lead_preview = "\n".join(lyrics_preview.splitlines()[:SIMPMUSIC_LEAD_LINES])

        signals = {
            "title": text_similarity(title, _simpmusic_title(candidate)),
            "artist": text_similarity(artist, cand_artist) if cand_artist else 0.0,
            "album": text_similarity(requested_album, cand_album) if requested_album and cand_album else 0.0,
            "title_in_lyrics": _title_coverage(
                requested_title, title_token_patterns, normalize_text(lyrics_preview)
            ),
            "title_in_lead": _title_coverage(
                requested_title, title_token_patterns, normalize_text(lead_preview)
            ),
        }
        score = 0.0
        for name, weight in SIMPMUSIC_SCORE_WEIGHTS.items():
            score += signals[name] * weight

        if score > best_score:
            best_score = score
            best_result = candidate

    if best_score < SIMPMUSIC_MIN_MATCH_SCORE:
        return None
    return best_result


def _simpmusic_cooldown_expiry() -> float:
    global _SIMPMUSIC_COOLDOWN_UNTIL

    with _SIMPMUSIC_COOLDOWN_LOCK:
        cache = lyrics_miss_cache()
        persistent_expiry = (
            cache.cooldown_until(_SIMPMUSIC_COOLDOWN_KEY) if cache else None
        )
        if persistent_expiry:
            _SIMPMUSIC_COOLDOWN_UNTIL = max(
                _SIMPMUSIC_COOLDOWN_UNTIL,
                persistent_expiry,
            )
        return _SIMPMUSIC_COOLDOWN_UNTIL


def _activate_simpmusic_cooldown() -> None:
    global _SIMPMUSIC_COOLDOWN_UNTIL, _SIMPMUSIC_NOTICE_UNTIL

    expires_at = time.time() + SIMPMUSIC_COOLDOWN_TTL
    with _SIMPMUSIC_COOLDOWN_LOCK:
        cache = lyrics_miss_cache()
        if cache:
            expires_at = cache.put_cooldown(
                _SIMPMUSIC_COOLDOWN_KEY,
                SIMPMUSIC_COOLDOWN_TTL,
            )
        _SIMPMUSIC_COOLDOWN_UNTIL = expires_at
        _SIMPMUSIC_NOTICE_UNTIL = expires_at

    print(
        f"  [simpmusic] Rate limited ({HTTPStatus.TOO_MANY_REQUESTS.value}); cooling down for {SIMPMUSIC_COOLDOWN_TTL // 60} minutes",
        file=sys.stderr,
    )


def _simpmusic_cooldown_active() -> bool:
    global _SIMPMUSIC_NOTICE_UNTIL

    expires_at = _simpmusic_cooldown_expiry()
    remaining = expires_at - time.time()
    if remaining <= 0:
        return False

    with _SIMPMUSIC_COOLDOWN_LOCK:
        if _SIMPMUSIC_NOTICE_UNTIL != expires_at:
            minutes = max(1, int((remaining + 59) // 60))
            print(
                f"  [simpmusic] Cooldown active ({minutes}m remaining); skipping",
                file=sys.stderr,
            )
            _SIMPMUSIC_NOTICE_UNTIL = expires_at
    return True


def _simpmusic_response(path: str, failure: str, **kwargs):
    response = http_get(f"{SIMPMUSIC_API_BASE}/{path}", timeout=DEFAULT_TIMEOUT, **kwargs)
    if response.status_code == HTTPStatus.TOO_MANY_REQUESTS:
        _activate_simpmusic_cooldown()
        return None
    return response if response_ok("simpmusic", failure, response) else None


def _simpmusic_results(payload: object) -> list | None:
    results = payload.get("data") if isinstance(payload, dict) else payload
    return results if isinstance(results, list) and results else None


def _simpmusic_details(payload: object) -> dict | None:
    details = payload.get("data") if isinstance(payload, dict) else None
    if isinstance(details, list):
        details = details[0] if details else None
    return details if isinstance(details, dict) else None


def _simpmusic_result(best: dict, details: dict, artist: str, title: str) -> ProviderResult | None:
    synced_lyrics = str(details.get("syncedLyrics") or details.get("lrc") or "").strip()
    plain_lyrics = str(details.get("plainLyrics") or details.get("lyrics") or "").strip()
    if not synced_lyrics and not plain_lyrics:
        print("  [simpmusic] No lyrics content returned", file=sys.stderr)
        return None

    result_artist = str(best.get("artistName") or artist)
    result_title = _simpmusic_title(best) or title
    synced = bool(synced_lyrics)
    body = synced_lyrics if synced else to_lrc_from_plain(plain_lyrics)
    print(f"  [simpmusic] Found {'synced' if synced else 'plain'} lyrics", file=sys.stderr)
    return build_result(
        "simpmusic",
        "\n".join(lrc_header(result_artist, result_title) + [body]),
        result_artist,
        result_title,
        synced,
    )


def fetch_lyrics_simpmusic(
    artist: str,
    title: str,
    album: str = "",
    expected_duration: float | None = None,
) -> ProviderResult | None:
    try:
        if _simpmusic_cooldown_active():
            return None

        print(f"  [simpmusic] Searching for: {artist} - {title}", file=sys.stderr)
        search_resp = _simpmusic_response("search", "Search failed", params={"q": f"{title} {artist}".strip()})
        if search_resp is None:
            return None

        results = _simpmusic_results(search_resp.json())
        if not results:
            print("  [simpmusic] No search results", file=sys.stderr)
            return None

        best = _pick_best_simpmusic_search_result(results, artist, title, album, expected_duration)
        if not best:
            print("  [simpmusic] No suitable match in search results", file=sys.stderr)
            return None

        video_id = best.get("videoId") or best.get("id")
        if not video_id:
            print("  [simpmusic] Search result missing video id", file=sys.stderr)
            return None

        details_resp = _simpmusic_response(video_id, "Lyrics fetch failed")
        if details_resp is None:
            return None

        details = _simpmusic_details(details_resp.json())
        if details is None:
            print("  [simpmusic] Invalid lyrics payload", file=sys.stderr)
            return None

        return _simpmusic_result(best, details, artist, title)

    except Exception as e:  # noqa: BLE001 - provider boundary
        print(f"  [simpmusic] Error: {e}", file=sys.stderr)
        return None

