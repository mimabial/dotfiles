#!/usr/bin/env python3
"""
Shared lyrics provider logic for both single-song and album batch workflows.

Features:
- Shared multi-source fetching for single-track and album workflows
- Synced-first strategy with plain fallback
- Optional fast parallel mode
- Lightweight metadata validation to reduce wrong-song matches
"""

from __future__ import annotations

import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from difflib import SequenceMatcher
from html import unescape
from typing import Callable, Dict, List, Optional, Tuple

import requests

try:
    from ytmusicapi import OAuthCredentials, YTMusic

    HAS_YTMUSIC = True
except ImportError:
    HAS_YTMUSIC = False

try:
    from lyricsgenius import Genius

    HAS_GENIUS = True
except ImportError:
    HAS_GENIUS = False

LRCLIB_API_SEARCH = "https://lrclib.net/api/search"
LRCLIB_API_GET = "https://lrclib.net/api/get"
LYRICSOVH_API = "https://api.lyrics.ovh/v1"
SIMPMUSIC_API_BASE = "https://api-lyrics.simpmusic.org/v1"
CHARTLYRICS_API = "https://api.chartlyrics.com/apiv1.asmx/SearchLyricDirect"
LYRICSFREEK_BASE = "https://www.lyricsfreek.com"
OAUTH_TOKEN_KEYS = {
    "scope",
    "token_type",
    "access_token",
    "refresh_token",
    "expires_at",
    "expires_in",
}

_YTMUSIC_CLIENT = None
_YTMUSIC_MODE = "uninitialized"
_GENIUS_CLIENT = None
DEFAULT_TIMEOUT = 10
SONG_MATCH_THRESHOLD = 0.72
ARTIST_MATCH_THRESHOLD = 0.68

ProviderResult = Dict[str, object]
ProviderFetcher = Callable[[str, str, str], Optional[ProviderResult]]
LYRICS_OVH_BOILERPLATE_PATTERNS = [
    re.compile(r"^\s*paroles?\s+de\s+la\s+chanson\b.*\bpar\b.+$", re.IGNORECASE),
    re.compile(r"^\s*lyrics?\s+(?:for|of)\b.*\bby\b.+$", re.IGNORECASE),
]


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _normalize_text(text: str) -> str:
    text = re.sub(r"[^\w\s]", " ", text or "")
    text = re.sub(r"\s+", " ", text)
    return text.lower().strip()


def _split_artists(artist_text: str) -> List[str]:
    if not artist_text:
        return []
    artist_text = re.sub(
        r"\s*(feat\.|ft\.|featuring|with|&|and)\s*",
        ",",
        artist_text,
        flags=re.IGNORECASE,
    )
    parts = re.split(r"\s*,\s*|\s*/\s*|\s*;\s*", artist_text)
    return [p for p in (_normalize_text(part) for part in parts) if p]


def _is_placeholder_artist(artist_text: str) -> bool:
    norm = _normalize_text(artist_text)
    return norm in {
        "",
        "unknown",
        "unknown artist",
        "various",
        "various artist",
        "various artists",
        "va",
    }


def _similarity(left: str, right: str) -> float:
    left_norm = _normalize_text(left)
    right_norm = _normalize_text(right)
    if not left_norm or not right_norm:
        return 0.0
    return SequenceMatcher(None, left_norm, right_norm).ratio()


def _extract_lrc_tag(lrc_text: str, tag: str) -> str:
    match = re.search(rf"^\[{tag}:(.*?)\]\s*$", lrc_text, flags=re.MULTILINE)
    if not match:
        return ""
    return match.group(1).strip()


def _is_lrc_synced(lrc_text: str) -> bool:
    timestamps: List[Tuple[int, int, int]] = []
    for line in lrc_text.splitlines():
        match = re.match(r"^\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]", line.strip())
        if not match:
            continue
        minutes = int(match.group(1))
        seconds = int(match.group(2))
        fraction = int((match.group(3) or "0").ljust(3, "0")[:3])
        timestamps.append((minutes, seconds, fraction))
    if not timestamps:
        return False
    return any(ts != (0, 0, 0) for ts in timestamps)


def _to_lrc_from_plain(plain_text: str) -> str:
    lines: List[str] = []
    for line in plain_text.splitlines():
        lines.append(f"[00:00.00]{line}")
    return "\n".join(lines)


def _strip_leading_boilerplate_lines(text: str, patterns: List[re.Pattern]) -> Tuple[str, int]:
    lines = text.splitlines()
    idx = 0
    removed = 0
    scanned = 0
    max_scan_lines = 6

    while idx < len(lines) and scanned < max_scan_lines:
        line = lines[idx].strip()
        scanned += 1

        if not line:
            idx += 1
            continue

        if any(pattern.match(line) for pattern in patterns):
            removed += 1
            idx += 1
            # Drop immediate blank lines after removed boilerplate.
            while idx < len(lines) and not lines[idx].strip():
                idx += 1
            continue

        break

    cleaned = "\n".join(lines[idx:]).strip()
    if not cleaned:
        return text.strip(), removed
    return cleaned, removed


def _build_result(
    source: str,
    lyrics: str,
    artist: str,
    title: str,
    synced: bool,
) -> ProviderResult:
    return {
        "source": source,
        "lyrics": lyrics,
        "artist": artist,
        "title": title,
        "synced": synced,
    }


def _is_oauth_token_file(token_path: str) -> bool:
    try:
        with open(token_path, encoding="utf-8") as f:
            payload = json.load(f)
        return isinstance(payload, dict) and OAUTH_TOKEN_KEYS.issubset(payload.keys())
    except Exception:
        return False


def _read_secret_file(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except Exception:
        return ""


def get_ytmusic_client():
    """
    Use OAuth only when explicitly configured; otherwise force unauthenticated
    mode. Browser-header auth files are intentionally not used.
    """
    global _YTMUSIC_CLIENT, _YTMUSIC_MODE
    if _YTMUSIC_MODE != "uninitialized":
        return _YTMUSIC_CLIENT

    if not HAS_YTMUSIC:
        _YTMUSIC_MODE = "unavailable"
        return None

    config_home = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
    ytmusic_config_dir = os.path.join(config_home, "ytmusicapi")

    oauth_file = os.path.expanduser(
        os.environ.get("YTMUSIC_OAUTH_FILE", os.path.join(ytmusic_config_dir, "oauth.json"))
    )
    oauth_client_id = os.environ.get("YTMUSIC_OAUTH_CLIENT_ID", "").strip()
    oauth_client_secret = os.environ.get("YTMUSIC_OAUTH_CLIENT_SECRET", "").strip()

    if not oauth_client_id:
        oauth_client_id = _read_secret_file(os.path.join(ytmusic_config_dir, "client_id"))
    if not oauth_client_secret:
        oauth_client_secret = _read_secret_file(
            os.path.join(ytmusic_config_dir, "client_secret")
        )

    if oauth_client_id and oauth_client_secret and _is_oauth_token_file(oauth_file):
        try:
            creds = OAuthCredentials(
                client_id=oauth_client_id, client_secret=oauth_client_secret
            )
            _YTMUSIC_CLIENT = YTMusic(auth=oauth_file, oauth_credentials=creds)
            _YTMUSIC_MODE = "oauth"
            return _YTMUSIC_CLIENT
        except Exception as e:
            print(
                f"  [ytmusic] OAuth init failed, falling back to unauthenticated mode: {e}",
                file=sys.stderr,
            )

    try:
        _YTMUSIC_CLIENT = YTMusic(auth=None)
        _YTMUSIC_MODE = "unauthenticated"
        return _YTMUSIC_CLIENT
    except Exception as e:
        _YTMUSIC_MODE = "init_failed"
        print(f"  [ytmusic] Client init failed: {e}", file=sys.stderr)
        return None


def fetch_lyrics_lrclib(
    artist: str,
    title: str,
    album: str = "",
    use_local_album: bool = True,
) -> Optional[ProviderResult]:
    try:
        print(f"  [lrclib] Searching for: {artist} - {title}", file=sys.stderr)

        search_params = {"track_name": title, "artist_name": artist}
        search_resp = requests.get(
            LRCLIB_API_SEARCH, params=search_params, timeout=DEFAULT_TIMEOUT
        )
        if search_resp.status_code != 200:
            print(
                f"  [lrclib] Search failed with status {search_resp.status_code}",
                file=sys.stderr,
            )
            return None

        results = search_resp.json()
        if not results:
            print("  [lrclib] No search results", file=sys.stderr)
            return None

        best_match = None
        for track in results:
            if album and track.get("albumName", "").lower() == album.lower():
                best_match = track
                break
        if not best_match:
            best_match = results[0]

        get_params = {
            "track_name": best_match["trackName"],
            "artist_name": best_match["artistName"],
            "album_name": best_match["albumName"],
            "duration": best_match["duration"],
        }
        get_resp = requests.get(
            LRCLIB_API_GET, params=get_params, timeout=DEFAULT_TIMEOUT
        )
        if get_resp.status_code != 200:
            print(
                f"  [lrclib] Get lyrics failed with status {get_resp.status_code}",
                file=sys.stderr,
            )
            return None

        data = get_resp.json()
        synced_lyrics = data.get("syncedLyrics")
        if not synced_lyrics:
            print("  [lrclib] No synced lyrics available", file=sys.stderr)
            return None

        lrc_lines = []
        lrc_lines.append(f"[ar:{data.get('artistName', artist)}]")
        lrc_lines.append(f"[ti:{data.get('trackName', title)}]")
        if use_local_album and album:
            lrc_lines.append(f"[al:{album}]")
        elif data.get("albumName"):
            lrc_lines.append(f"[al:{data.get('albumName')}]")
        if data.get("duration"):
            duration_sec = data["duration"]
            minutes = int(duration_sec // 60)
            seconds = duration_sec % 60
            lrc_lines.append(f"[length:{minutes:02d}:{seconds:05.2f}]")
        lrc_lines.append("")
        lrc_lines.append(synced_lyrics)

        print("  [lrclib] Found synced lyrics", file=sys.stderr)
        return _build_result(
            "lrclib",
            "\n".join(lrc_lines),
            data.get("artistName", artist),
            data.get("trackName", title),
            True,
        )

    except Exception as e:
        print(f"  [lrclib] Error: {e}", file=sys.stderr)
        return None


def _extract_yt_line_text(line: object) -> str:
    if isinstance(line, str):
        return line
    if isinstance(line, dict):
        return str(line.get("text") or line.get("line") or "").strip()
    return str(getattr(line, "text", "")).strip()


def _extract_yt_line_start_ms(line: object) -> Optional[int]:
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
    except Exception:
        return None


def _payload_to_plain_lines(payload: object) -> List[str]:
    if isinstance(payload, str):
        return payload.splitlines()
    if isinstance(payload, list):
        lines: List[str] = []
        for entry in payload:
            text = _extract_yt_line_text(entry)
            if text:
                lines.append(text)
        return lines
    return []


def _extract_yt_song_title(song_info: dict, fallback: str) -> str:
    title = str(song_info.get("title") or song_info.get("name") or "").strip()
    return title or fallback


def _extract_yt_song_artist(song_info: dict, fallback: str) -> str:
    artists: List[str] = []
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


def _extract_yt_album_name(song_info: dict) -> str:
    album = song_info.get("album")
    if isinstance(album, dict):
        return str(album.get("name") or "").strip()
    if isinstance(album, str):
        return album.strip()
    return str(song_info.get("albumName") or "").strip()


def fetch_lyrics_youtube(artist: str, title: str) -> Optional[ProviderResult]:
    if not HAS_YTMUSIC:
        print("  [ytmusic] Skipped (ytmusicapi not installed)", file=sys.stderr)
        return None

    try:
        ytmusic = get_ytmusic_client()
        if ytmusic is None:
            print("  [ytmusic] Skipped (client unavailable)", file=sys.stderr)
            return None

        print(f"  [ytmusic] Searching for: {artist} - {title}", file=sys.stderr)
        search_query = f"{title} {artist}"
        search_results = ytmusic.search(query=search_query, filter="songs", limit=1)
        if not search_results:
            print("  [ytmusic] No search results", file=sys.stderr)
            return None

        song_info = search_results[0]
        matched_title = _extract_yt_song_title(song_info, title)
        matched_artist = _extract_yt_song_artist(song_info, artist)
        matched_album = _extract_yt_album_name(song_info)
        video_id = song_info.get("videoId")
        if not video_id:
            print("  [ytmusic] No videoId found", file=sys.stderr)
            return None

        watch_playlist = ytmusic.get_watch_playlist(videoId=video_id)
        lyrics_browse_id = watch_playlist.get("lyrics")
        if not lyrics_browse_id:
            print("  [ytmusic] No lyrics browseId", file=sys.stderr)
            return None

        lyrics_data = ytmusic.get_lyrics(browseId=lyrics_browse_id)
        if not lyrics_data or not lyrics_data.get("lyrics"):
            print("  [ytmusic] No lyrics data", file=sys.stderr)
            return None

        lrc_lines = []
        lrc_lines.append(f"[ar:{matched_artist}]")
        lrc_lines.append(f"[ti:{matched_title}]")
        if matched_album:
            lrc_lines.append(f"[al:{matched_album}]")
        if song_info.get("duration_seconds"):
            duration_sec = song_info["duration_seconds"]
            minutes = int(duration_sec // 60)
            seconds = duration_sec % 60
            lrc_lines.append(f"[length:{minutes:02d}:{seconds:05.2f}]")
        lrc_lines.append("")

        lyrics_payload = lyrics_data.get("lyrics")
        synced = False

        if lyrics_data.get("hasTimestamps") and isinstance(lyrics_payload, list):
            for line in lyrics_payload:
                start_ms = _extract_yt_line_start_ms(line)
                text = _extract_yt_line_text(line)
                if start_ms is None or not text:
                    continue
                minutes = start_ms // 60000
                seconds = (start_ms % 60000) / 1000
                lrc_lines.append(f"[{minutes:02d}:{seconds:05.2f}]{text}")
            synced = _is_lrc_synced("\n".join(lrc_lines))
            if synced:
                print("  [ytmusic] Found synced lyrics", file=sys.stderr)
        else:
            for line in _payload_to_plain_lines(lyrics_payload):
                lrc_lines.append(f"[00:00.00]{line}")
            print("  [ytmusic] Found plain lyrics (no timestamps)", file=sys.stderr)

        if not synced and len(lrc_lines) <= 4:
            return None

        return _build_result(
            "ytmusic",
            "\n".join(lrc_lines),
            matched_artist,
            matched_title,
            synced,
        )

    except Exception as e:
        print(f"  [ytmusic] Error: {e}", file=sys.stderr)
        return None


def _pick_best_simpmusic_search_result(
    results: List[dict],
    artist: str,
    title: str,
    album: str = "",
    expected_duration: Optional[float] = None,
) -> Optional[dict]:
    best_result = None
    best_score = -1.0

    requested_title = _normalize_text(title)
    requested_album = _normalize_text(album)

    for candidate in results[:8]:
        if not isinstance(candidate, dict):
            continue

        cand_title = str(
            candidate.get("songTitle")
            or candidate.get("title")
            or candidate.get("name")
            or ""
        )
        cand_artist = str(candidate.get("artistName") or candidate.get("artist") or "")
        cand_album = str(candidate.get("albumName") or candidate.get("album") or "")

        title_score = _similarity(title, cand_title)
        artist_score = _similarity(artist, cand_artist) if cand_artist else 0.0

        album_score = 0.0
        if requested_album and cand_album:
            album_score = _similarity(requested_album, cand_album)

        lyrics_preview = str(
            candidate.get("plainLyric")
            or candidate.get("plainLyrics")
            or candidate.get("lyrics")
            or ""
        )
        lyrics_preview_norm = _normalize_text(lyrics_preview)
        lead_preview = "\n".join(lyrics_preview.splitlines()[:3])
        lead_preview_norm = _normalize_text(lead_preview)
        title_in_lyrics = 0.0
        if requested_title and lyrics_preview_norm:
            if requested_title in lyrics_preview_norm:
                title_in_lyrics = 1.0
            else:
                title_tokens = [tok for tok in requested_title.split() if len(tok) > 1]
                if title_tokens:
                    hits = sum(
                        1
                        for token in title_tokens
                        if re.search(rf"\b{re.escape(token)}\b", lyrics_preview_norm)
                    )
                    title_in_lyrics = hits / len(title_tokens)

        title_in_lead = 0.0
        if requested_title and lead_preview_norm:
            if requested_title in lead_preview_norm:
                title_in_lead = 1.0
            else:
                title_tokens = [tok for tok in requested_title.split() if len(tok) > 1]
                if title_tokens:
                    hits = sum(
                        1
                        for token in title_tokens
                        if re.search(rf"\b{re.escape(token)}\b", lead_preview_norm)
                    )
                    title_in_lead = hits / len(title_tokens)

        # Prefer strong title/artist matches and reward lyrics previews that actually
        # contain the requested title phrase/tokens, especially near the start.
        # Duration is intentionally excluded because SimpMusic duration metadata is
        # inconsistent for duplicate title/artist candidates.
        score = (
            title_score * 0.45
            + artist_score * 0.25
            + album_score * 0.15
            + title_in_lyrics * 0.05
            + title_in_lead * 0.10
        )

        if score > best_score:
            best_score = score
            best_result = candidate

    if best_score < 0.35:
        return None
    return best_result


def fetch_lyrics_simpmusic(
    artist: str,
    title: str,
    album: str = "",
    expected_duration: Optional[float] = None,
) -> Optional[ProviderResult]:
    try:
        print(f"  [simpmusic] Searching for: {artist} - {title}", file=sys.stderr)

        query = f"{title} {artist}".strip()
        search_resp = requests.get(
            f"{SIMPMUSIC_API_BASE}/search",
            params={"q": query},
            timeout=DEFAULT_TIMEOUT,
        )
        if search_resp.status_code != 200:
            print(
                f"  [simpmusic] Search failed with status {search_resp.status_code}",
                file=sys.stderr,
            )
            return None

        search_payload = search_resp.json()
        if isinstance(search_payload, dict):
            raw_results = search_payload.get("data")
        else:
            raw_results = search_payload

        if not isinstance(raw_results, list) or not raw_results:
            print("  [simpmusic] No search results", file=sys.stderr)
            return None

        best = _pick_best_simpmusic_search_result(
            raw_results,
            artist,
            title,
            album,
            expected_duration,
        )
        if not best:
            print("  [simpmusic] No suitable match in search results", file=sys.stderr)
            return None

        video_id = best.get("videoId") or best.get("id")
        if not video_id:
            print("  [simpmusic] Search result missing video id", file=sys.stderr)
            return None

        details_resp = requests.get(
            f"{SIMPMUSIC_API_BASE}/{video_id}",
            timeout=DEFAULT_TIMEOUT,
        )
        if details_resp.status_code != 200:
            print(
                f"  [simpmusic] Lyrics fetch failed with status {details_resp.status_code}",
                file=sys.stderr,
            )
            return None

        details_payload = details_resp.json()
        details_data = details_payload.get("data") if isinstance(details_payload, dict) else None
        if isinstance(details_data, list):
            details_data = details_data[0] if details_data else None
        if not isinstance(details_data, dict):
            print("  [simpmusic] Invalid lyrics payload", file=sys.stderr)
            return None

        synced_lyrics = str(
            details_data.get("syncedLyrics") or details_data.get("lrc") or ""
        ).strip()
        plain_lyrics = str(
            details_data.get("plainLyrics") or details_data.get("lyrics") or ""
        ).strip()
        if not synced_lyrics and not plain_lyrics:
            print("  [simpmusic] No lyrics content returned", file=sys.stderr)
            return None

        result_artist = str(best.get("artistName") or artist)
        result_title = str(
            best.get("songTitle")
            or best.get("title")
            or best.get("name")
            or title
        )
        lrc_lines = [f"[ar:{result_artist}]", f"[ti:{result_title}]", ""]

        if synced_lyrics:
            lrc_lines.append(synced_lyrics)
            synced = True
            print("  [simpmusic] Found synced lyrics", file=sys.stderr)
        else:
            lrc_lines.append(_to_lrc_from_plain(plain_lyrics))
            synced = False
            print("  [simpmusic] Found plain lyrics", file=sys.stderr)

        return _build_result(
            "simpmusic",
            "\n".join(lrc_lines),
            result_artist,
            result_title,
            synced,
        )

    except Exception as e:
        print(f"  [simpmusic] Error: {e}", file=sys.stderr)
        return None


def get_genius_client():
    global _GENIUS_CLIENT

    if _GENIUS_CLIENT is not None:
        return _GENIUS_CLIENT
    if not HAS_GENIUS:
        return None

    token = os.environ.get("GENIUS_TOKEN", "").strip() or os.environ.get(
        "GENIUS_ACCESS_TOKEN", ""
    ).strip()
    if not token:
        return None

    try:
        try:
            _GENIUS_CLIENT = Genius(
                token,
                skip_non_songs=True,
                remove_section_headers=True,
                verbose=False,
                timeout=DEFAULT_TIMEOUT,
            )
        except TypeError:
            # Older lyricsgenius versions may not support timeout kwarg.
            _GENIUS_CLIENT = Genius(
                token,
                skip_non_songs=True,
                remove_section_headers=True,
                verbose=False,
            )
        return _GENIUS_CLIENT
    except Exception as e:
        print(f"  [genius] Client init failed: {e}", file=sys.stderr)
        return None


def _cleanup_genius_lyrics(text: str) -> str:
    cleaned = text.strip()
    cleaned = re.sub(r"\n?\d*Embed\s*$", "", cleaned, flags=re.IGNORECASE)
    return cleaned.strip()


def fetch_lyrics_genius(artist: str, title: str) -> Optional[ProviderResult]:
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

        lyrics_text = _cleanup_genius_lyrics(str(song.lyrics))
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

    except Exception as e:
        print(f"  [genius] Error: {e}", file=sys.stderr)
        return None


def fetch_lyrics_chartlyrics(artist: str, title: str) -> Optional[ProviderResult]:
    try:
        print(f"  [chartlyrics] Searching for: {artist} - {title}", file=sys.stderr)
        response = requests.get(
            CHARTLYRICS_API,
            params={"artist": artist, "song": title},
            timeout=DEFAULT_TIMEOUT,
        )
        if response.status_code != 200:
            print(
                f"  [chartlyrics] Request failed with status {response.status_code}",
                file=sys.stderr,
            )
            return None
        if "<Lyric>" not in response.text:
            print("  [chartlyrics] No lyrics in response", file=sys.stderr)
            return None

        root = ET.fromstring(response.text)
        lyric_text = (root.findtext(".//Lyric") or "").strip()
        if not lyric_text:
            print("  [chartlyrics] Empty lyric field", file=sys.stderr)
            return None

        result_artist = (root.findtext(".//LyricArtist") or artist).strip() or artist
        result_title = (root.findtext(".//LyricSong") or title).strip() or title

        lrc_lines = [f"[ar:{result_artist}]", f"[ti:{result_title}]", ""]
        lrc_lines.append(_to_lrc_from_plain(lyric_text))

        print("  [chartlyrics] Found plain lyrics", file=sys.stderr)
        return _build_result(
            "chartlyrics",
            "\n".join(lrc_lines),
            result_artist,
            result_title,
            False,
        )
    except ET.ParseError as e:
        print(f"  [chartlyrics] XML parse error: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  [chartlyrics] Error: {e}", file=sys.stderr)
        return None


def _slugify_lyricsfreek(value: str) -> str:
    slug = _normalize_text(value).replace(" ", "-")
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug


def _strip_html_tags(text: str) -> str:
    text = re.sub(r"(?is)<br\s*/?>", "\n", text)
    text = re.sub(r"(?is)<[^>]+>", "", text)
    return unescape(text)


def fetch_lyrics_lyricsfreek(artist: str, title: str) -> Optional[ProviderResult]:
    try:
        print(f"  [lyricsfreek] Searching for: {artist} - {title}", file=sys.stderr)
        artist_slug = _slugify_lyricsfreek(artist)
        title_slug = _slugify_lyricsfreek(title)
        if not artist_slug or not title_slug:
            return None

        response = requests.get(
            f"{LYRICSFREEK_BASE}/{artist_slug}/{title_slug}-lyrics",
            headers={"User-Agent": "Mozilla/5.0 (compatible; LyricsFetcher/1.0)"},
            timeout=DEFAULT_TIMEOUT,
            allow_redirects=True,
        )
        if response.status_code != 200:
            print(
                f"  [lyricsfreek] Request failed with status {response.status_code}",
                file=sys.stderr,
            )
            return None

        lyrics_match = re.search(
            r'(?is)<div[^>]*class=["\']lyrics["\'][^>]*>(.*?)</div>',
            response.text,
        )
        if not lyrics_match:
            print("  [lyricsfreek] No lyrics block found", file=sys.stderr)
            return None

        lyrics_text = _strip_html_tags(lyrics_match.group(1))
        lyrics_text = re.sub(
            r"\n*Submit Corrections.*",
            "",
            lyrics_text,
            flags=re.IGNORECASE | re.DOTALL,
        ).strip()
        if not lyrics_text:
            print("  [lyricsfreek] Empty lyrics payload", file=sys.stderr)
            return None

        lrc_lines = [f"[ar:{artist}]", f"[ti:{title}]", ""]
        lrc_lines.append(_to_lrc_from_plain(lyrics_text))

        print("  [lyricsfreek] Found plain lyrics", file=sys.stderr)
        return _build_result(
            "lyricsfreek",
            "\n".join(lrc_lines),
            artist,
            title,
            False,
        )
    except Exception as e:
        print(f"  [lyricsfreek] Error: {e}", file=sys.stderr)
        return None


def fetch_lyrics_lyricsovh(artist: str, title: str) -> Optional[ProviderResult]:
    try:
        print(f"  [lyrics.ovh] Searching for: {artist} - {title}", file=sys.stderr)
        url = f"{LYRICSOVH_API}/{artist}/{title}"
        response = requests.get(url, timeout=DEFAULT_TIMEOUT)
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
    except Exception as e:
        print(f"  [lyrics.ovh] Error: {e}", file=sys.stderr)
        return None


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
