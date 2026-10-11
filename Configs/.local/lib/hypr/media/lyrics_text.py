from __future__ import annotations

import re
from collections.abc import Callable
from difflib import SequenceMatcher


ProviderResult = dict[str, object]


ProviderFetcher = Callable[[str, str, str], ProviderResult | None]


LYRICS_OVH_BOILERPLATE_PATTERNS = [
    re.compile(r"^\s*paroles?\s+de\s+la\s+chanson\b.*\bpar\b.+$", re.IGNORECASE),
    re.compile(r"^\s*lyrics?\s+(?:for|of)\b.*\bby\b.+$", re.IGNORECASE),
]


_NON_WORD_RX = re.compile(r"[^\w\s]")


_WHITESPACE_RX = re.compile(r"\s+")


_FEAT_RX = re.compile(r"\s*(feat\.|ft\.|featuring|with|&|and)\s*", re.IGNORECASE)


_ARTIST_SPLIT_RX = re.compile(r"\s*,\s*|\s*/\s*|\s*;\s*")


PLAIN_LRC_TIMESTAMP = "[00:00.00]"


_LRC_TIMESTAMP_RX = re.compile(r"^\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]")


def normalize_text(text: str) -> str:
    text = _NON_WORD_RX.sub(" ", text or "")
    text = _WHITESPACE_RX.sub(" ", text)
    return text.lower().strip()


def split_artists(artist_text: str) -> list[str]:
    if not artist_text:
        return []
    artist_text = _FEAT_RX.sub(",", artist_text)
    parts = _ARTIST_SPLIT_RX.split(artist_text)
    return [p for p in (normalize_text(part) for part in parts) if p]


def is_placeholder_artist(artist_text: str) -> bool:
    norm = normalize_text(artist_text)
    return norm in {
        "",
        "unknown",
        "unknown artist",
        "various",
        "various artist",
        "various artists",
        "va",
    }


def text_similarity(left: str, right: str) -> float:
    left_norm = normalize_text(left)
    right_norm = normalize_text(right)
    if not left_norm or not right_norm:
        return 0.0
    return SequenceMatcher(None, left_norm, right_norm).ratio()


def extract_lrc_tag(lrc_text: str, tag: str) -> str:
    match = re.search(rf"^\[{tag}:(.*?)\]\s*$", lrc_text, flags=re.MULTILINE)
    if not match:
        return ""
    return match.group(1).strip()


def is_lrc_synced(lrc_text: str) -> bool:
    timestamps: list[tuple[int, int, int]] = []
    for line in lrc_text.splitlines():
        match = _LRC_TIMESTAMP_RX.match(line.strip())
        if not match:
            continue
        minutes = int(match.group(1))
        seconds = int(match.group(2))
        fraction = int((match.group(3) or "0").ljust(3, "0")[:3])
        timestamps.append((minutes, seconds, fraction))
    if not timestamps:
        return False
    return any(ts != (0, 0, 0) for ts in timestamps)


def to_lrc_from_plain(plain_text: str) -> str:
    lines: list[str] = []
    for line in plain_text.splitlines():
        lines.append(f"{PLAIN_LRC_TIMESTAMP}{line}")
    return "\n".join(lines)


def strip_leading_boilerplate_lines(text: str, patterns: list[re.Pattern]) -> tuple[str, int]:
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
            while idx < len(lines) and not lines[idx].strip():
                idx += 1
            continue

        break

    cleaned = "\n".join(lines[idx:]).strip()
    if not cleaned:
        return text.strip(), removed
    return cleaned, removed


def build_result(
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


def _lrc_length(seconds: float) -> str:
    return f"{int(seconds // 60):02d}:{seconds % 60:05.2f}"


def lrc_timestamp(start_ms: int) -> str:
    return f"[{start_ms // 60000:02d}:{(start_ms % 60000) / 1000:05.2f}]"


def lrc_header(artist: str, title: str, album: str = "", duration: float | None = None) -> list[str]:
    header = [f"[ar:{artist}]", f"[ti:{title}]"]
    if album:
        header.append(f"[al:{album}]")
    if duration:
        header.append(f"[length:{_lrc_length(duration)}]")
    return header + [""]

