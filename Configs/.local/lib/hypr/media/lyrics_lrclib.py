from __future__ import annotations

import sys
from lyrics_text import ProviderResult, build_result, lrc_header
from lyrics_http import DEFAULT_TIMEOUT, response_ok, http_get


LRCLIB_API_SEARCH = "https://lrclib.net/api/search"


LRCLIB_API_GET = "https://lrclib.net/api/get"


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
        if not response_ok("lrclib", "Search failed", search_resp):
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
        if not response_ok("lrclib", "Get lyrics failed", get_resp):
            return None

        data = get_resp.json()
        synced_lyrics = data.get("syncedLyrics")
        if not synced_lyrics:
            print("  [lrclib] No synced lyrics available", file=sys.stderr)
            return None

        result_artist = data.get("artistName", artist)
        result_title = data.get("trackName", title)
        header = lrc_header(
            result_artist,
            result_title,
            album if use_local_album and album else data.get("albumName") or "",
            data.get("duration"),
        )
        print("  [lrclib] Found synced lyrics", file=sys.stderr)
        return build_result("lrclib", "\n".join(header + [synced_lyrics]), result_artist, result_title, True)

    except Exception as e:  # noqa: BLE001 - provider boundary
        print(f"  [lrclib] Error: {e}", file=sys.stderr)
        return None

