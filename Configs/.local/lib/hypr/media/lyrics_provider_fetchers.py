#!/usr/bin/env python3
"""Provider-specific lyrics fetchers."""

from __future__ import annotations

import os
import re
import sys
import xml.etree.ElementTree as ET
from html import unescape
from typing import List, Optional

import requests

try:
    from lyricsgenius import Genius

    HAS_GENIUS = True
except ImportError:
    HAS_GENIUS = False

from lyrics_provider_common import (
    CHARTLYRICS_API,
    DEFAULT_TIMEOUT,
    HAS_YTMUSIC,
    LRCLIB_API_GET,
    LRCLIB_API_SEARCH,
    LYRICSFREEK_BASE,
    LYRICSOVH_API,
    LYRICS_OVH_BOILERPLATE_PATTERNS,
    ProviderResult,
    SIMPMUSIC_API_BASE,
    _build_result,
    _is_lrc_synced,
    _normalize_text,
    _similarity,
    _strip_leading_boilerplate_lines,
    _to_lrc_from_plain,
    get_ytmusic_client,
)

_GENIUS_CLIENT = None

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
        matched_title = str(song_info.get("title") or song_info.get("name") or "").strip() or title
        matched_artist = _extract_yt_song_artist(song_info, artist)
        album = song_info.get("album")
        if isinstance(album, dict):
            matched_album = str(album.get("name") or "").strip()
        elif isinstance(album, str):
            matched_album = album.strip()
        else:
            matched_album = str(song_info.get("albumName") or "").strip()
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
    title_tokens = [tok for tok in requested_title.split() if len(tok) > 1]
    title_token_rxes = [re.compile(rf"\b{re.escape(tok)}\b") for tok in title_tokens]

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
            elif title_token_rxes:
                hits = sum(1 for rx in title_token_rxes if rx.search(lyrics_preview_norm))
                title_in_lyrics = hits / len(title_token_rxes)

        title_in_lead = 0.0
        if requested_title and lead_preview_norm:
            if requested_title in lead_preview_norm:
                title_in_lead = 1.0
            elif title_token_rxes:
                hits = sum(1 for rx in title_token_rxes if rx.search(lead_preview_norm))
                title_in_lead = hits / len(title_token_rxes)

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

        lyrics_text = re.sub(r"(?is)<br\s*/?>", "\n", lyrics_match.group(1))
        lyrics_text = re.sub(r"(?is)<[^>]+>", "", lyrics_text)
        lyrics_text = unescape(lyrics_text)
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
