from __future__ import annotations

import sys
from lyrics_text import PLAIN_LRC_TIMESTAMP, ProviderResult, build_result, is_lrc_synced, lrc_header, lrc_timestamp
from lyrics_youtube_client import HAS_YTMUSIC, get_ytmusic_client


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
            lines.append(f"{lrc_timestamp(start_ms)}{text}")
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

        header = lrc_header(matched_artist, matched_title, matched_album, song_info.get("duration_seconds"))
        lyrics_payload = lyrics_data.get("lyrics")
        if lyrics_data.get("hasTimestamps") and isinstance(lyrics_payload, list):
            body = _yt_timed_lines(lyrics_payload)
            synced = is_lrc_synced("\n".join(header + body))
            if synced:
                print("  [ytmusic] Found synced lyrics", file=sys.stderr)
        else:
            body = [f"{PLAIN_LRC_TIMESTAMP}{line}" for line in _payload_to_plain_lines(lyrics_payload)]
            synced = False
            print("  [ytmusic] Found plain lyrics (no timestamps)", file=sys.stderr)

        if not body:
            return None

        return build_result("ytmusic", "\n".join(header + body), matched_artist, matched_title, synced)

    except Exception as e:  # noqa: BLE001 - third-party client boundary
        print(f"  [ytmusic] Error: {e}", file=sys.stderr)
        return None

