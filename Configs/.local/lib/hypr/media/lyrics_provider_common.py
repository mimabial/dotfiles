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
