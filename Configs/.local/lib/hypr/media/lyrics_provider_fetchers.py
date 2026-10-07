#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

try:
    from lyricsgenius import Genius

    HAS_GENIUS = True
except ImportError:
    HAS_GENIUS = False

from lyrics_cache import lyrics_miss_cache
from lyrics_provider_common import (
    DEFAULT_TIMEOUT,
    HAS_YTMUSIC,
    LRCLIB_API_GET,
    LRCLIB_API_SEARCH,
    LYRICS_OVH_BOILERPLATE_PATTERNS,
    LYRICSOVH_API,
    SIMPMUSIC_API_BASE,
    ProviderResult,
    _build_result,
    _is_lrc_synced,
    _normalize_text,
    _similarity,
    _strip_leading_boilerplate_lines,
    _to_lrc_from_plain,
    get_ytmusic_client,
    http_get,
)

_GENIUS_CLIENT = None
_GENIUS_TOKEN_KEYS = ("GENIUS_TOKEN", "GENIUS_ACCESS_TOKEN")
_GENIUS_WORKER_FLAG = "--genius-worker"
GENIUS_WORKER_TIMEOUT = DEFAULT_TIMEOUT * 4 + 5
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


def _parse_env_value(raw_value: str) -> str:
    """Parse the limited value syntax needed by the private Genius env file."""
    value = raw_value.strip()
    if not value:
        return ""

    if value[0] in {"'", '"'}:
        quote = value[0]
        closing_quote = value.find(quote, 1)
        if closing_quote == -1:
            return ""
        remainder = value[closing_quote + 1 :].strip()
        if remainder and not remainder.startswith("#"):
            return ""
        return value[1:closing_quote]

    return value.split(" #", 1)[0].strip()


def _genius_token_from_file() -> str:
    config_home = Path(
        os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
    ).expanduser()
    env_file = config_home / "genius" / "env"

    try:
        if env_file.stat().st_mode & 0o077:
            print(
                f"  [genius] Ignoring {env_file} "
                "(group/other permissions are not allowed)",
                file=sys.stderr,
            )
            return ""
        lines = env_file.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return ""
    except OSError as error:
        print(f"  [genius] Cannot read {env_file}: {error}", file=sys.stderr)
        return ""

    values: dict[str, str] = {}
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()

        key, separator, raw_value = line.partition("=")
        key = key.strip()
        if not separator or key not in _GENIUS_TOKEN_KEYS:
            continue

        value = _parse_env_value(raw_value)
        if value:
            values[key] = value

    return next((values[key] for key in _GENIUS_TOKEN_KEYS if values.get(key)), "")


def get_genius_token() -> str:
    return next(
        (
            token
            for key in _GENIUS_TOKEN_KEYS
            if (token := os.environ.get(key, "").strip())
        ),
        "",
    ) or _genius_token_from_file()


def _response_ok(provider: str, failure: str, response) -> bool:
    if response.status_code == 200:
        return True
    print(f"  [{provider}] {failure} with status {response.status_code}", file=sys.stderr)
    return False


def _lrc_length(seconds: float) -> str:
    return f"{int(seconds // 60):02d}:{seconds % 60:05.2f}"


def _lrc_timestamp(start_ms: int) -> str:
    return f"[{start_ms // 60000:02d}:{(start_ms % 60000) / 1000:05.2f}]"


def _lrc_header(artist: str, title: str, album: str = "", duration: float | None = None) -> list[str]:
    header = [f"[ar:{artist}]", f"[ti:{title}]"]
    if album:
        header.append(f"[al:{album}]")
    if duration:
        header.append(f"[length:{_lrc_length(duration)}]")
    return header + [""]


def _lrclib_pick_track(results: list[dict], album: str) -> dict:
    if album:
        for track in results:
            if track.get("albumName", "").lower() == album.lower():
                return track
    return results[0]


def fetch_lyrics_lrclib(
    artist: str,
    title: str,
    album: str = "",
    use_local_album: bool = True,
) -> ProviderResult | None:
    try:
        print(f"  [lrclib] Searching for: {artist} - {title}", file=sys.stderr)

        search_resp = http_get(
            LRCLIB_API_SEARCH,
            params={"track_name": title, "artist_name": artist},
            timeout=DEFAULT_TIMEOUT,
        )
        if not _response_ok("lrclib", "Search failed", search_resp):
            return None

        results = search_resp.json()
        if not results:
            print("  [lrclib] No search results", file=sys.stderr)
            return None

        track = _lrclib_pick_track(results, album)
        get_resp = http_get(
            LRCLIB_API_GET,
            params={
                "track_name": track["trackName"],
                "artist_name": track["artistName"],
                "album_name": track["albumName"],
                "duration": track["duration"],
            },
            timeout=DEFAULT_TIMEOUT,
        )
        if not _response_ok("lrclib", "Get lyrics failed", get_resp):
            return None

        data = get_resp.json()
        synced_lyrics = data.get("syncedLyrics")
        if not synced_lyrics:
            print("  [lrclib] No synced lyrics available", file=sys.stderr)
            return None

        result_artist = data.get("artistName", artist)
        result_title = data.get("trackName", title)
        header = _lrc_header(
            result_artist,
            result_title,
            album if use_local_album and album else data.get("albumName") or "",
            data.get("duration"),
        )
        print("  [lrclib] Found synced lyrics", file=sys.stderr)
        return _build_result("lrclib", "\n".join(header + [synced_lyrics]), result_artist, result_title, True)

    except Exception as e:  # noqa: BLE001 - provider boundary
        print(f"  [lrclib] Error: {e}", file=sys.stderr)
        return None


def _extract_yt_line_text(line: object) -> str:
    if isinstance(line, str):
        return line
    if isinstance(line, dict):
        return str(line.get("text") or line.get("line") or "").strip()
    return str(getattr(line, "text", "")).strip()


def _extract_yt_line_start_ms(line: object) -> int | None:
    value = None
    if isinstance(line, dict):
        value = (
            line.get("start_time")
            or line.get("startTime")
            or line.get("startTimeMs")
            or line.get("start")
        )
    else:
        value = getattr(line, "start_time", None)
    try:
        if value is None:
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def _payload_to_plain_lines(payload: object) -> list[str]:
    if isinstance(payload, str):
        return payload.splitlines()
    if isinstance(payload, list):
        lines: list[str] = []
        for entry in payload:
            text = _extract_yt_line_text(entry)
            if text:
                lines.append(text)
        return lines
    return []


def _extract_yt_song_artist(song_info: dict, fallback: str) -> str:
    artists: list[str] = []
    raw_artists = song_info.get("artists")

    if isinstance(raw_artists, list):
        for item in raw_artists:
            if isinstance(item, dict):
                name = str(item.get("name") or item.get("artist") or "").strip()
            else:
                name = str(item).strip()
            if name and name not in artists:
                artists.append(name)
    elif isinstance(raw_artists, dict):
        name = str(raw_artists.get("name") or raw_artists.get("artist") or "").strip()
        if name:
            artists.append(name)

    if not artists:
        fallback_artist = str(song_info.get("artist") or "").strip()
        if fallback_artist:
            artists.append(fallback_artist)

    if artists:
        return ", ".join(artists)
    return fallback


def _extract_yt_song_album(song_info: dict) -> str:
    album = song_info.get("album")
    if isinstance(album, dict):
        return str(album.get("name") or "").strip()
    if isinstance(album, str):
        return album.strip()
    return str(song_info.get("albumName") or "").strip()


def _yt_timed_lines(payload: list) -> list[str]:
    lines = []
    for line in payload:
        start_ms = _extract_yt_line_start_ms(line)
        text = _extract_yt_line_text(line)
        if start_ms is not None and text:
            lines.append(f"{_lrc_timestamp(start_ms)}{text}")
    return lines


def fetch_lyrics_youtube(artist: str, title: str) -> ProviderResult | None:
    if not HAS_YTMUSIC:
        print("  [ytmusic] Skipped (ytmusicapi not installed)", file=sys.stderr)
        return None

    try:
        ytmusic = get_ytmusic_client()
        if ytmusic is None:
            print("  [ytmusic] Skipped (client unavailable)", file=sys.stderr)
            return None

        print(f"  [ytmusic] Searching for: {artist} - {title}", file=sys.stderr)
        search_results = ytmusic.search(query=f"{title} {artist}", filter="songs", limit=1)
        if not search_results:
            print("  [ytmusic] No search results", file=sys.stderr)
            return None

        song_info = search_results[0]
        matched_title = str(song_info.get("title") or song_info.get("name") or "").strip() or title
        matched_artist = _extract_yt_song_artist(song_info, artist)
        matched_album = _extract_yt_song_album(song_info)
        video_id = song_info.get("videoId")
        if not video_id:
            print("  [ytmusic] No videoId found", file=sys.stderr)
            return None

        lyrics_browse_id = ytmusic.get_watch_playlist(videoId=video_id).get("lyrics")
        if not lyrics_browse_id:
            print("  [ytmusic] No lyrics browseId", file=sys.stderr)
            return None

        lyrics_data = ytmusic.get_lyrics(browseId=lyrics_browse_id, timestamps=True)
        if not lyrics_data or not lyrics_data.get("lyrics"):
            print("  [ytmusic] No lyrics data", file=sys.stderr)
            return None

        header = _lrc_header(matched_artist, matched_title, matched_album, song_info.get("duration_seconds"))
        lyrics_payload = lyrics_data.get("lyrics")
        if lyrics_data.get("hasTimestamps") and isinstance(lyrics_payload, list):
            body = _yt_timed_lines(lyrics_payload)
            synced = _is_lrc_synced("\n".join(header + body))
            if synced:
                print("  [ytmusic] Found synced lyrics", file=sys.stderr)
        else:
            body = [f"[00:00.00]{line}" for line in _payload_to_plain_lines(lyrics_payload)]
            synced = False
            print("  [ytmusic] Found plain lyrics (no timestamps)", file=sys.stderr)

        if not body:
            return None

        return _build_result("ytmusic", "\n".join(header + body), matched_artist, matched_title, synced)

    except Exception as e:  # noqa: BLE001 - third-party client boundary
        print(f"  [ytmusic] Error: {e}", file=sys.stderr)
        return None


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

    requested_title = _normalize_text(title)
    requested_album = _normalize_text(album)
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
            "title": _similarity(title, _simpmusic_title(candidate)),
            "artist": _similarity(artist, cand_artist) if cand_artist else 0.0,
            "album": _similarity(requested_album, cand_album) if requested_album and cand_album else 0.0,
            "title_in_lyrics": _title_coverage(
                requested_title, title_token_patterns, _normalize_text(lyrics_preview)
            ),
            "title_in_lead": _title_coverage(
                requested_title, title_token_patterns, _normalize_text(lead_preview)
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
        "  [simpmusic] Rate limited (429); cooling down for 1 hour",
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
    if response.status_code == 429:
        _activate_simpmusic_cooldown()
        return None
    return response if _response_ok("simpmusic", failure, response) else None


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
    body = synced_lyrics if synced else _to_lrc_from_plain(plain_lyrics)
    print(f"  [simpmusic] Found {'synced' if synced else 'plain'} lyrics", file=sys.stderr)
    return _build_result(
        "simpmusic",
        "\n".join(_lrc_header(result_artist, result_title) + [body]),
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


def get_genius_client():
    global _GENIUS_CLIENT

    if _GENIUS_CLIENT is not None:
        return _GENIUS_CLIENT
    if not HAS_GENIUS:
        return None

    token = get_genius_token()
    if not token:
        return None

    try:
        try:
            _GENIUS_CLIENT = Genius(
                token,
                skip_non_songs=True,
                remove_section_headers=True,
                timeout=DEFAULT_TIMEOUT,
            )
        except TypeError as error:
            if "timeout" not in str(error):
                raise
            # Older lyricsgenius versions may not support timeout kwarg.
            _GENIUS_CLIENT = Genius(
                token,
                skip_non_songs=True,
                remove_section_headers=True,
            )
        return _GENIUS_CLIENT
    except Exception as e:  # noqa: BLE001 - third-party client boundary
        print(f"  [genius] Client init failed: {e}", file=sys.stderr)
        return None


def _fetch_lyrics_genius_direct(artist: str, title: str) -> ProviderResult | None:
    if not HAS_GENIUS:
        print("  [genius] Skipped (lyricsgenius not installed)", file=sys.stderr)
        return None

    client = get_genius_client()
    if client is None:
        print("  [genius] Skipped (token/client unavailable)", file=sys.stderr)
        return None

    try:
        print(f"  [genius] Searching for: {artist} - {title}", file=sys.stderr)
        song = client.search_song(title, artist)
        if song is None or not getattr(song, "lyrics", None):
            print("  [genius] No lyrics found", file=sys.stderr)
            return None

        lyrics_text = str(song.lyrics).strip()
        lyrics_text = re.sub(r"\n?\d*Embed\s*$", "", lyrics_text, flags=re.IGNORECASE).strip()
        if not lyrics_text:
            print("  [genius] Empty lyrics payload", file=sys.stderr)
            return None

        result_artist = str(getattr(song, "artist", "") or artist).strip()
        result_title = str(getattr(song, "title", "") or title).strip()
        lrc_lines = [f"[ar:{result_artist}]", f"[ti:{result_title}]", ""]
        lrc_lines.append(_to_lrc_from_plain(lyrics_text))

        print("  [genius] Found plain lyrics", file=sys.stderr)
        return _build_result(
            "genius",
            "\n".join(lrc_lines),
            result_artist,
            result_title,
            False,
        )

    except Exception as error:  # noqa: BLE001 - third-party client boundary
        message = str(error).split("Response body:", 1)[0].strip()
        print(f"  [genius] Error: {message or type(error).__name__}", file=sys.stderr)
        return None


def _fetch_lyrics_genius_excluded(
    mullvad_exclude: str,
    artist: str,
    title: str,
) -> ProviderResult | None:
    command = [
        mullvad_exclude,
        sys.executable,
        str(Path(__file__).resolve()),
        _GENIUS_WORKER_FLAG,
        artist,
        title,
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=GENIUS_WORKER_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"  [genius] Split-tunnel worker failed: {error}", file=sys.stderr)
        return None

    if completed.stderr:
        print(completed.stderr.rstrip(), file=sys.stderr)
    if completed.returncode != 0:
        print(
            f"  [genius] Split-tunnel worker exited with status "
            f"{completed.returncode}",
            file=sys.stderr,
        )
        return None

    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        print(f"  [genius] Invalid worker response: {error}", file=sys.stderr)
        return None

    if result is None:
        return None
    if not isinstance(result, dict) or not isinstance(result.get("lyrics"), str):
        print("  [genius] Invalid worker result", file=sys.stderr)
        return None
    return result


def fetch_lyrics_genius(artist: str, title: str) -> ProviderResult | None:
    mullvad_exclude = shutil.which("mullvad-exclude")
    if mullvad_exclude:
        return _fetch_lyrics_genius_excluded(mullvad_exclude, artist, title)
    return _fetch_lyrics_genius_direct(artist, title)


def fetch_lyrics_lyricsovh(artist: str, title: str) -> ProviderResult | None:
    try:
        print(f"  [lyrics.ovh] Searching for: {artist} - {title}", file=sys.stderr)
        url = f"{LYRICSOVH_API}/{artist}/{title}"
        response = http_get(url, timeout=DEFAULT_TIMEOUT)
        if response.status_code == 200:
            data = response.json()
            lyrics_text = data.get("lyrics", "").strip()
            if lyrics_text:
                lyrics_text, stripped = _strip_leading_boilerplate_lines(
                    lyrics_text, LYRICS_OVH_BOILERPLATE_PATTERNS
                )
                if stripped:
                    print(
                        f"  [lyrics.ovh] Stripped {stripped} boilerplate line(s)",
                        file=sys.stderr,
                    )
                if not lyrics_text:
                    print("  [lyrics.ovh] Empty lyrics payload", file=sys.stderr)
                    return None
                print("  [lyrics.ovh] Found plain lyrics", file=sys.stderr)
                lrc_lines = [f"[ar:{artist}]", f"[ti:{title}]", ""]
                lrc_lines.append(_to_lrc_from_plain(lyrics_text))
                return _build_result(
                    "lyrics.ovh",
                    "\n".join(lrc_lines),
                    artist,
                    title,
                    False,
                )

        print("  [lyrics.ovh] No lyrics found", file=sys.stderr)
        return None
    except Exception as e:  # noqa: BLE001 - provider boundary
        print(f"  [lyrics.ovh] Error: {e}", file=sys.stderr)
        return None


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 3 or args[0] != _GENIUS_WORKER_FLAG:
        print("This module provides internal lyrics fetchers.", file=sys.stderr)
        return 2

    result = _fetch_lyrics_genius_direct(args[1], args[2])
    json.dump(result, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
