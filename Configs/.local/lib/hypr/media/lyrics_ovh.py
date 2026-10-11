from __future__ import annotations

import sys
from lyrics_text import LYRICS_OVH_BOILERPLATE_PATTERNS, ProviderResult, build_result, lrc_header, strip_leading_boilerplate_lines, to_lrc_from_plain
from http import HTTPStatus

from lyrics_http import DEFAULT_TIMEOUT, http_get


LYRICSOVH_API = "https://api.lyrics.ovh/v1"


def fetch_lyrics_lyricsovh(artist: str, title: str) -> ProviderResult | None:
    try:
        print(f"  [lyrics.ovh] Searching for: {artist} - {title}", file=sys.stderr)
        url = f"{LYRICSOVH_API}/{artist}/{title}"
        response = http_get(url, timeout=DEFAULT_TIMEOUT)
        if response.status_code == HTTPStatus.OK:
            data = response.json()
            lyrics_text = data.get("lyrics", "").strip()
            if lyrics_text:
                lyrics_text, stripped = strip_leading_boilerplate_lines(
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
                lrc_lines = lrc_header(artist, title)
                lrc_lines.append(to_lrc_from_plain(lyrics_text))
                return build_result(
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

