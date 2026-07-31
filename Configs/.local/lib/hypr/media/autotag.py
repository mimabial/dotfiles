#!/usr/bin/env python3
"""
Look up track metadata online and write it into .mp3/.opus tags.

Identification is by acoustic fingerprint (chromaprint -> AcoustID) when an API
key is available, otherwise by text search against MusicBrainz using existing
tags or the filename.

Exit codes:
  0 = every file resolved (or nothing to do)
  1 = at least one file could not be identified
  2 = internal/runtime error
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import unicodedata
from collections import Counter
from difflib import SequenceMatcher
from pathlib import Path

import requests
from mutagen import MutagenError
from mutagen.easyid3 import EasyID3
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3, ID3NoHeaderError
from mutagen.mp3 import MP3
from mutagen.oggopus import OggOpus

from lyrics_paths import music_library_dir
from ytdlp_config import ytdlp_auth_args

ACOUSTID_ENDPOINT = "https://api.acoustid.org/v2/lookup"
MUSICBRAINZ_ENDPOINT = "https://musicbrainz.org/ws/2/recording"
ITUNES_ENDPOINT = "https://itunes.apple.com/search"
DEEZER_ENDPOINT = "https://api.deezer.com/search"
DEEZER_TRACK_ENDPOINT = "https://api.deezer.com/track"
CONTACT = os.environ.get("AUTOTAG_CONTACT", "hyprshell-autotag")
USER_AGENT = f"hyprshell-autotag/1.0 ( {CONTACT} )"
HTTP_SESSION = requests.Session()
HTTP_SESSION.headers.update({"User-Agent": USER_AGENT})

# MusicBrainz allows one request per second per client and blocks abusers.
MUSICBRAINZ_INTERVAL = 1.1
ACOUSTID_INTERVAL = 0.34
# Apple publishes no firm figure; the 429 backoff absorbs whatever the real one is.
ITUNES_INTERVAL = 1.2
DEEZER_INTERVAL = 0.2

# Rescans should not repeat an unchanged lookup. Successful metadata changes
# slowly; misses and temporary provider blocks are retried after one hour.
CACHE_VERSION = 1
CACHE_SUCCESS_TTL = 99 * 24 * 60 * 60
CACHE_MISS_TTL = 60 * 60
DEEZER_COOLDOWN = 60 * 60

# MusicBrainz scores matches 0-100; below this a hit is usually a different song.
MUSICBRAINZ_MIN_SCORE = 90

# Independent of the weighted score. Measured: worst true 0.51, best false 0.44.
# Not raisable to 0.60: correct pairs like "ru. & Magixx"/"ru." also score 0.50.
MIN_TITLE_SIMILARITY = 0.50
MIN_ARTIST_SIMILARITY = 0.50
MIN_ALBUM_SIMILARITY = 0.60

# "vidéo"/"vídeo" appear as often as "video" on francophone and lusophone uploads.
_VIDEO = r"v[ií]d[eé]o"
_NOISE_TAG = (
    rf"(?:official\s+)?(?:music\s+|lyrics?\s+|audio\s+|performance\s+)?{_VIDEO}"
    r"(?:\s+(?:hd|hq|4k|8k))?"
    rf"|{_VIDEO}\s+clip"
    r"|(?:official\s+)?lyrics?\s+visuali[sz]er"
    rf"|official\s+(?:audio|visuali[sz]er|performance\s+{_VIDEO})"
    rf"|{_VIDEO}\s+(?:oficial|officielle?)"
    r"|clip\s+officiel(?:le)?|(?:official\s+)?(?:audio\s+only|full\s+stream)"
    rf"|(?:\w+\s+)?{_VIDEO}"
    r"|prod(?:uced)?\.?\s+by\s+[^)\]】）｝]*"
    r"|lyrics?|audio|visuali[sz]er|mv|hd|hq|4k|8k"
    r"|remaster(?:ed)?(?:\s+\d{4})?"
    r"|explicit|clean|official"
)
# Uploaders often append a year: "(Clip Officiel) 2018".
_NOISE_YEAR = r"(?:\s+\d{4})?"

# CJK and fullwidth brackets included: Japanese uploads annotate with 【MV】.
_OPEN, _CLOSE = r"[\(\[【（｛]", r"[\)\]】）｝]"

# "(Official Video by NS PICTURES)" — a production credit trailing the boilerplate.
_NOISE_CREDIT = r"(?:\s*by\s+[^)\]】）｝]*)?"

NOISE_BRACKET = re.compile(
    rf"\s*{_OPEN}\s*(?:{_NOISE_TAG}){_NOISE_YEAR}{_NOISE_CREDIT}\s*{_CLOSE}{_NOISE_YEAR}",
    re.I,
)

# Unbracketed, a bare keyword is not enough: "India.Arie - Video" is a real title,
# so the trailing form demands a qualifier that only boilerplate carries.
_NOISE_TAG_QUALIFIED = (
    r"(?:official(?:\s+(?:music|lyrics?))?|music|lyrics?|performance)\s+v[ií]d[eé]o"
    r"|v[ií]d[eé]o\s+(?:officielle?|oficial|clip|lyrics?)"
    r"|clip\s+officiel(?:le)?"
    r"|official\s+(?:audio|visuali[sz]er)"
    r"|(?:official\s+)?(?:audio\s+only|full\s+stream)"
)
# Kept in step with strip_title_noise in ~/.config/rmpc/lib/fetch_lyrics.
# May be followed by a real bracket group: "Title | Music Video (Story Book Riddim)".
NOISE_TRAILING = re.compile(
    rf"\s*[|｜:-]\s*(?:{_NOISE_TAG_QUALIFIED}){_NOISE_YEAR}(?=\s*$|\s*{_OPEN})", re.I
)

PROVIDERS = ("deezer", "itunes", "musicbrainz")
# iTunes leads as the only provider returning a genre; it costs ~5.4s to Deezer's ~0.3s.
DEFAULT_PROVIDER_ORDER = "itunes,deezer,musicbrainz"

# A lookup is only worth its round trip if one of these is still empty.
FILL_FIELDS = ("title", "artist", "album", "date", "tracknumber", "genre")

# iTunes serves any size by substituting into the URL; 600px is ~85KB against
# 231KB for 1000px, matching what yt-dlp embeds for new downloads.
ARTWORK_SIZE = "600x600bb.jpg"
# Carried alongside the tags but never written as one.
NON_TAG_FIELDS = {"artwork_url", "_preserved_credits"}

SUPPORTED = {".mp3", ".opus", ".flac"}
# Opus and FLAC both carry Vorbis comments, which are conventionally uppercase.
VORBIS = {".opus", ".flac"}
FIELDS = ("title", "artist", "album", "albumartist", "tracknumber", "date")


class Unidentified(Exception):
    pass


# Set once Deezer 403s, so the rest of the run skips it instead of paying a
# request each time to be refused.
DEEZER_REFUSED = "deezer refused this address (403)"
_deezer_blocked = False
_persistent_cache = None


def _disable_deezer() -> None:
    global _deezer_blocked
    if not _deezer_blocked:
        _deezer_blocked = True
        if _persistent_cache is not None:
            _persistent_cache.put_state("deezer_blocked", DEEZER_COOLDOWN)
        print("deezer refused this address; skipping it for the rest of the run",
              file=sys.stderr)


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))


def cache_home() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))


def acoustid_key() -> str:
    key = os.environ.get("ACOUSTID_API_KEY", "").strip()
    if key:
        return key
    token_file = config_home() / "acoustid" / "api.token"
    if token_file.is_file():
        return token_file.read_text(encoding="utf-8").strip()
    return ""


class ResolutionCache:
    """Persistent final lookup results, including expiring catalog misses."""

    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path, timeout=5)
        os.chmod(path, 0o600)
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS resolutions (
                cache_key TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                expires_at REAL NOT NULL
            )
            """
        )
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS state (
                state_key TEXT PRIMARY KEY,
                expires_at REAL NOT NULL
            )
            """
        )
        self.connection.execute(
            "DELETE FROM resolutions WHERE expires_at <= ?",
            (time.time(),),
        )
        self.connection.execute(
            "DELETE FROM state WHERE expires_at <= ?",
            (time.time(),),
        )
        self.connection.commit()
        self.hits = 0
        self.misses = 0

    def get(self, cache_key: str) -> dict | None:
        row = self.connection.execute(
            "SELECT payload, expires_at FROM resolutions WHERE cache_key = ?",
            (cache_key,),
        ).fetchone()
        if row is None:
            self.misses += 1
            return None
        if row[1] <= time.time():
            self.connection.execute(
                "DELETE FROM resolutions WHERE cache_key = ?",
                (cache_key,),
            )
            self.connection.commit()
            self.misses += 1
            return None
        try:
            payload = json.loads(row[0])
        except (TypeError, json.JSONDecodeError):
            self.connection.execute(
                "DELETE FROM resolutions WHERE cache_key = ?",
                (cache_key,),
            )
            self.connection.commit()
            self.misses += 1
            return None
        self.hits += 1
        return payload

    def put(self, cache_key: str, payload: dict, ttl: int) -> None:
        self.connection.execute(
            """
            INSERT INTO resolutions(cache_key, payload, expires_at)
            VALUES (?, ?, ?)
            ON CONFLICT(cache_key) DO UPDATE SET
                payload = excluded.payload,
                expires_at = excluded.expires_at
            """,
            (cache_key, json.dumps(payload, ensure_ascii=False), time.time() + ttl),
        )
        self.connection.commit()

    def state_active(self, state_key: str) -> bool:
        row = self.connection.execute(
            "SELECT expires_at FROM state WHERE state_key = ?",
            (state_key,),
        ).fetchone()
        return row is not None and row[0] > time.time()

    def put_state(self, state_key: str, ttl: int) -> None:
        self.connection.execute(
            """
            INSERT INTO state(state_key, expires_at)
            VALUES (?, ?)
            ON CONFLICT(state_key) DO UPDATE SET expires_at = excluded.expires_at
            """,
            (state_key, time.time() + ttl),
        )
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()


def configure_persistent_cache(cache: ResolutionCache | None) -> None:
    global _deezer_blocked, _persistent_cache
    _persistent_cache = cache
    _deezer_blocked = bool(cache and cache.state_active("deezer_blocked"))


class RateLimiter:
    def __init__(self, interval: float) -> None:
        self.interval = interval
        self._last = 0.0

    def wait(self) -> None:
        delta = time.monotonic() - self._last
        if delta < self.interval:
            time.sleep(self.interval - delta)
        self._last = time.monotonic()


def http_get(url: str, params: dict, limiter: RateLimiter, attempts: int = 4):
    """MusicBrainz answers 503 when throttled or busy; that is worth retrying."""
    delay = 2.0
    response = None
    for attempt in range(attempts):
        limiter.wait()
        response = HTTP_SESSION.get(url, params=params, timeout=20)
        if response.status_code in (429, 503) and attempt < attempts - 1:
            time.sleep(delay)
            delay *= 2
            continue
        break
    response.raise_for_status()
    return response


def fingerprint(path: Path) -> tuple[int, str]:
    proc = subprocess.run(
        ["fpcalc", "-json", str(path)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise Unidentified(f"fpcalc failed: {proc.stderr.strip()}")
    data = json.loads(proc.stdout)
    return int(data["duration"]), data["fingerprint"]


def parse_filename(path: Path) -> tuple[str, str]:
    """Best-effort '<artist> - <title>' split, with track numbers stripped."""
    stem = re.sub(r"^\s*\d{1,3}\s*[-._)]\s*", "", path.stem)
    if " - " in stem:
        artist, _, title = stem.partition(" - ")
        return artist.strip(), title.strip()
    return "", stem.strip()


def read_tags(path: Path):
    suffix = path.suffix.lower()
    if suffix == ".opus":
        return OggOpus(path)
    if suffix == ".flac":
        return FLAC(path)
    try:
        return EasyID3(path)
    except ID3NoHeaderError:
        audio = MP3(path)
        audio.add_tags()
        return EasyID3(path)


def existing(tags, key: str) -> str:
    value = tags.get(key) or tags.get(key.upper())
    if not value:
        return ""
    if isinstance(value, list):
        return str(value[0]).strip()
    return str(value).strip()


def pick_release(recording: dict, album: str = "") -> dict:
    """Prefer an album over singles/compilations, then the earliest release."""
    groups = recording.get("releasegroups") or []
    if not groups:
        return {}
    if album:
        groups = [
            group
            for group in groups
            if album_agrees(group.get("title", ""), album)
        ]
        if not groups:
            return {}
    albums = [g for g in groups if (g.get("type") or "").lower() == "album"]
    return (albums or groups)[0]


def from_acoustid(
    path: Path,
    key: str,
    limiter: RateLimiter,
    min_score: float,
    candidates: list[tuple[str, str]] | None = None,
    album: str = "",
) -> dict:
    duration, fp = fingerprint(path)
    response = http_get(
        ACOUSTID_ENDPOINT,
        {
            "client": key,
            "duration": duration,
            "fingerprint": fp,
            # requests encodes spaces as the `+` separators expected by the
            # AcoustID API. Literal plus signs become `%2B` and suppress the
            # requested recording metadata.
            "meta": "recordings releasegroups compress",
        },
        limiter,
    )
    payload = response.json()
    if payload.get("status") != "ok":
        raise Unidentified(f"acoustid: {payload.get('error', {}).get('message', 'error')}")

    for result in sorted(payload.get("results", []), key=lambda r: r.get("score", 0), reverse=True):
        if result.get("score", 0) < min_score:
            break
        recordings = [r for r in result.get("recordings") or [] if r.get("title")]
        if candidates:
            ranked = []
            for recording in recordings:
                artists = recording.get("artists") or []
                credited = ", ".join(a["name"] for a in artists if a.get("name"))
                agreements = []
                for artist, title in candidates:
                    _, wanted_credit, _ = track_identity(artist, title)
                    if (
                        title_similarity(recording["title"], title)
                        >= MIN_TITLE_SIMILARITY
                        and artist_agrees(credited, wanted_credit)
                    ):
                        agreements.append(
                            match_score(credited, recording["title"], artist, title)
                        )
                if agreements:
                    ranked.append((max(agreements), recording))
            recordings = [
                recording
                for _, recording in sorted(ranked, key=lambda item: item[0], reverse=True)
            ]

        for recording in recordings:
            artists = recording.get("artists") or []
            group = pick_release(recording, album)
            if album and not group:
                continue
            return {
                "title": recording["title"],
                "artist": ", ".join(a["name"] for a in artists if a.get("name")),
                "album": group.get("title", ""),
                "albumartist": ", ".join(
                    a["name"] for a in (group.get("artists") or []) if a.get("name")
                ),
                "musicbrainz_trackid": recording.get("id", ""),
                "musicbrainz_releasegroupid": group.get("id", ""),
            }
    raise Unidentified("no acoustid match above threshold")


def normalize(value: str) -> list[str]:
    folded = unicodedata.normalize("NFKD", value.lower())
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    folded = re.sub(r"\b(?:feat|ft|featuring|with)\b", " ", folded)
    folded = re.sub(r"[^0-9a-z]+", " ", folded)
    return folded.split()


def similarity(left: str, right: str) -> float:
    """Token overlap and sequence ratio, whichever is kinder. Credits differ in
    separators far more often than in content ("A, B" vs "A & B")."""
    a, b = normalize(left), normalize(right)
    if not a or not b:
        return 0.0
    overlap = len(set(a) & set(b)) / len(set(a) | set(b))
    ratio = SequenceMatcher(None, " ".join(a), " ".join(b)).ratio()
    return max(overlap, ratio)


def has_non_latin(text: str) -> bool:
    return any(c.isalpha() and ord(c) > 0x24F for c in text)


def same_script(left: str, right: str) -> bool:
    return has_non_latin(left) == has_non_latin(right)


def artist_agrees(candidate: str, artist: str) -> bool:
    """Credits differ by separators and extra features, not by spelling, so a real
    match shares at least one word. Character similarity alone rates unrelated
    short names highly ("BAYLI" vs "Valiant" scores 0.50 on no shared word)."""
    if not artist:
        return True
    # Single characters are not evidence: "Ost [G]" and "Potato-g" share only "g".
    shared = {t for t in set(normalize(candidate)) & set(normalize(artist)) if len(t) > 1}
    if not shared:
        return False
    return similarity(candidate, artist) >= MIN_ARTIST_SIMILARITY


def title_similarity(candidate: str, title: str) -> float:
    candidate_base, _, _ = track_identity("", candidate)
    title_base, _, _ = track_identity("", title)
    return similarity(candidate_base, title_base)


def credit_similarity(
    cand_artist: str,
    cand_title: str,
    artist: str,
    title: str,
) -> float:
    _, candidate_credit, _ = track_identity(cand_artist, cand_title)
    _, wanted_credit, _ = track_identity(artist, title)
    return similarity(candidate_credit, wanted_credit)


def candidate_agrees(
    cand_artist: str,
    cand_title: str,
    artist: str,
    title: str,
) -> bool:
    """Match title identity separately from credits.

    Providers disagree on whether a featured artist belongs in the title or the
    artist credit. An explicit local feature must still be present somewhere in
    the provider result; otherwise a solo recording can steal the match.
    """
    _, candidate_credit, _ = track_identity(cand_artist, cand_title)
    _, wanted_credit, wanted_features = track_identity(artist, title)
    if title_similarity(cand_title, title) < MIN_TITLE_SIMILARITY:
        return False
    if not artist_agrees(candidate_credit, wanted_credit):
        return False
    return not wanted_features or credit_contains(candidate_credit, wanted_features)


def match_score(cand_artist: str, cand_title: str, artist: str, title: str) -> float:
    title_score = title_similarity(cand_title, title)
    if not artist:
        return title_score
    return 0.6 * title_score + 0.4 * credit_similarity(
        cand_artist, cand_title, artist, title
    )


def strip_release_suffix(album: str) -> str:
    return re.sub(r"\s*-\s*(?:Single|EP)\s*$", "", album, flags=re.I).strip()


def album_similarity(candidate: str, album: str) -> float:
    return similarity(strip_release_suffix(candidate), strip_release_suffix(album))


def album_agrees(candidate: str, album: str) -> bool:
    return not album or album_similarity(candidate, album) >= MIN_ALBUM_SIMILARITY


ITUNES_COMPILATION = re.compile(
    r"\((?:dj\s+mix|mixed)\)|\bgreatest\s+hits\b|\bcompilation\b|\bnow\s+that'?s\b", re.I
)


def primary_artist(album_artist: str, artist: str) -> str:
    """The name a release belongs to, so players do not file every collaboration
    as its own artist. Providers name it outright; otherwise the credit leads
    with it."""
    if album_artist:
        return album_artist
    lead = re.split(r"\s*(?:,|&|;|\bfeat\.?\b|\bft\.?\b|\bwith\b)\s*", artist, maxsplit=1)[0]
    return lead.strip()


def itunes_is_compilation(item: dict) -> bool:
    """A collection credited to someone other than the track's artist is a
    various-artists release, not the single it came from."""
    if ITUNES_COMPILATION.search(item.get("collectionName") or ""):
        return True
    collection_artist = item.get("collectionArtistName") or ""
    return bool(collection_artist) and (
        similarity(collection_artist, item.get("artistName", "")) < MIN_ARTIST_SIMILARITY
    )


def from_itunes(
    artist: str,
    title: str,
    limiter: RateLimiter,
    threshold: float,
    album: str = "",
) -> dict:
    if not title:
        raise Unidentified("no title to search with")

    cleaned = clean_title(title)
    results = []
    seen_results = set()
    for query_artist, query_title in search_variants(artist, cleaned):
        response = http_get(
            ITUNES_ENDPOINT,
            {
                "term": f"{query_artist} {query_title}".strip(),
                "media": "music",
                "entity": "song",
                "limit": 25,
            },
            limiter,
        )
        for item in response.json().get("results") or []:
            key = item.get("trackId") or (
                item.get("artistName", ""),
                item.get("trackName", ""),
                item.get("collectionName", ""),
            )
            if key not in seen_results:
                seen_results.add(key)
                results.append(item)
    if not results:
        raise Unidentified("no itunes match")

    best = None
    best_score = 0.0
    best_solo = None
    best_solo_score = 0.0
    best_album = None
    best_album_rank = (0.0, 0.0)
    rejected = 0.0
    for item in results:
        cand_artist = item.get("artistName", "")
        cand_title = item.get("trackName", "")
        score = match_score(cand_artist, cand_title, artist, cleaned)
        if not candidate_agrees(cand_artist, cand_title, artist, cleaned):
            rejected = max(rejected, score)
            continue
        if score > best_score:
            best, best_score = item, score
        if not itunes_is_compilation(item) and score > best_solo_score:
            best_solo, best_solo_score = item, score
        candidate_album = item.get("collectionName", "")
        if album_agrees(candidate_album, album):
            rank = (album_similarity(candidate_album, album), score)
            if rank > best_album_rank:
                best_album, best_album_rank = item, rank

    # A DJ mix's album and track number describe the mix, not the song. Only trade
    # down to one if the artist still agrees at least as well: the right song on a
    # mix beats the wrong artist on a studio release.
    if album:
        if best_album is None or best_album_rank[1] < threshold:
            raise Unidentified("no itunes match on requested album")
        best, best_score = best_album, best_album_rank[1]
    else:
        if (
            best_solo is not None
            and best_solo_score >= threshold
            and artist
            and credit_similarity(
                best_solo.get("artistName", ""),
                best_solo.get("trackName", ""),
                artist,
                cleaned,
            ) < credit_similarity(
                best.get("artistName", ""),
                best.get("trackName", ""),
                artist,
                cleaned,
            )
        ):
            best_solo = None
        if best_solo is not None and best_solo_score >= threshold:
            best, best_score = best_solo, best_solo_score

    if best is None or best_score < threshold:
        detail = f"{best_score:.2f}"
        if best is None and rejected:
            detail = f"{rejected:.2f}, failed title/artist gate"
        raise Unidentified(f"itunes best match too weak ({detail})")

    # A matching album hint makes an intentional DJ mix/compilation safe. Without
    # one, keep its grouping metadata out of a standalone track.
    compilation = itunes_is_compilation(best) and not album
    track_no = ""
    if best.get("trackNumber") and not compilation:
        track_no = str(best["trackNumber"])
        if best.get("trackCount"):
            track_no += f"/{best['trackCount']}"

    return {
        "title": best.get("trackName", ""),
        "artist": best.get("artistName", ""),
        "albumartist": "" if compilation else primary_artist(
            best.get("collectionArtistName") or "", best.get("artistName", "")
        ),
        "album": "" if compilation else strip_release_suffix(best.get("collectionName", "")),
        "date": "" if compilation else (best.get("releaseDate") or "")[:4],
        "tracknumber": track_no,
        "genre": best.get("primaryGenreName", ""),
        "artwork_url": (best.get("artworkUrl100") or "").replace(
            "100x100bb.jpg", ARTWORK_SIZE
        ),
    }


def from_deezer(
    artist: str,
    title: str,
    limiter: RateLimiter,
    threshold: float,
    album: str = "",
) -> dict:
    if not title:
        raise Unidentified("no title to search with")
    if _deezer_blocked:
        raise Unidentified(DEEZER_REFUSED)

    cleaned = clean_title(title)
    results = []
    seen_results = set()
    try:
        for query_artist, query_title in search_variants(artist, cleaned):
            response = http_get(
                DEEZER_ENDPOINT,
                {"q": f"{query_artist} {query_title}".strip()},
                limiter,
            )
            for item in response.json().get("data") or []:
                key = item.get("id") or (
                    (item.get("artist") or {}).get("name", ""),
                    item.get("title", ""),
                    (item.get("album") or {}).get("title", ""),
                )
                if key not in seen_results:
                    seen_results.add(key)
                    results.append(item)
    except requests.HTTPError as exc:
        # A sustained burst of unauthenticated lookups earns an edge block on the
        # whole API, not just the query. Stand down and let the chain continue.
        if exc.response is not None and exc.response.status_code == 403:
            _disable_deezer()
            if not results:
                raise Unidentified(DEEZER_REFUSED) from exc
        else:
            raise
    if not results:
        raise Unidentified("no deezer match")

    best = None
    best_score = 0.0
    best_rank = (0.0, 0.0)
    rejected = 0.0
    for item in results:
        cand_artist = (item.get("artist") or {}).get("name", "")
        cand_title = item.get("title", "")
        score = match_score(cand_artist, cand_title, artist, cleaned)
        if not candidate_agrees(cand_artist, cand_title, artist, cleaned):
            rejected = max(rejected, score)
            continue
        candidate_album = (item.get("album") or {}).get("title", "")
        if not album_agrees(candidate_album, album):
            continue
        rank = (album_similarity(candidate_album, album), score) if album else (score, 0.0)
        if rank > best_rank:
            best, best_score = item, score
            best_rank = rank

    if best is None or best_score < threshold:
        if album:
            raise Unidentified("no deezer match on requested album")
        detail = f"{best_score:.2f}"
        if best is None and rejected:
            detail = f"{rejected:.2f}, failed title/artist gate"
        raise Unidentified(f"deezer best match too weak ({detail})")

    dz_artist = (best.get("artist") or {}).get("name", "")
    meta = {
        "title": best.get("title", ""),
        "artist": dz_artist,
        "albumartist": primary_artist("", dz_artist),
        "album": strip_release_suffix((best.get("album") or {}).get("title", "")),
        "artwork_url": (best.get("album") or {}).get("cover_big", ""),
    }

    # Search hits omit the release date and track position; the track resource has them.
    if best.get("id"):
        try:
            detail = http_get(f"{DEEZER_TRACK_ENDPOINT}/{best['id']}", {}, limiter).json()
            meta["date"] = (detail.get("release_date") or "")[:4]
            if detail.get("track_position"):
                meta["tracknumber"] = str(detail["track_position"])
        except requests.RequestException:
            pass
    return meta


def clean_title(title: str) -> str:
    cleaned = title.replace("⧸", "/")
    cleaned = NOISE_BRACKET.sub("", cleaned)
    cleaned = NOISE_TRAILING.sub("", cleaned)
    cleaned = re.sub(r"\s*-\s*Topic\s*$", "", cleaned, flags=re.I)
    return re.sub(r"\s{2,}", " ", cleaned).strip(" -–—")


BRACKETED_FEATURE = re.compile(
    r"\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s+"
    r"(?P<who>[^)\]]+?)\s*[\)\]]",
    re.IGNORECASE,
)
TRAILING_FEATURE = re.compile(
    r"\s+(?:feat\.?|ft\.?|featuring)\s+(?P<who>.+?)\s*$",
    re.IGNORECASE,
)


def split_featured_title(title: str) -> tuple[str, str]:
    """Return a base title and credits carried by feature annotations."""
    featured = []

    def remove(match: re.Match) -> str:
        who = match.group("who").strip()
        if who:
            featured.append(who)
        return ""

    base = BRACKETED_FEATURE.sub(remove, clean_title(title))
    base = TRAILING_FEATURE.sub(remove, base)
    base = re.sub(r"\s{2,}", " ", base).strip(" -–—")
    return base, ", ".join(featured)


def credit_contains(credit: str, wanted: str) -> bool:
    wanted_tokens = set(normalize(wanted))
    return bool(wanted_tokens) and wanted_tokens <= set(normalize(credit))


def combine_credits(artist: str, featured: str) -> str:
    artist = artist.strip()
    featured = featured.strip()
    if not featured or credit_contains(artist, featured):
        return artist
    return ", ".join(value for value in (artist, featured) if value)


def track_identity(artist: str, title: str) -> tuple[str, str, str]:
    """Canonical fields used only for lookup; original metadata remains intact."""
    base_title, featured = split_featured_title(title)
    return base_title, combine_credits(artist, featured), featured


_CREDIT_SEPARATOR = re.compile(
    r"\s*(?:,|&|;|\bfeat(?:uring)?\b\.?|\bft\b\.?|\bwith\b)\s*",
    re.IGNORECASE,
)
CREDIT_NAME_SIMILARITY = 0.90
CREDIT_RECOVERY_TITLE_SIMILARITY = 0.80


def credit_names(artist: str, title: str = "") -> list[str]:
    """Return distinct credited names while keeping names containing 'and' whole."""
    _, combined_credit, _ = track_identity(artist, title)
    names: list[str] = []
    for raw_name in _CREDIT_SEPARATOR.split(combined_credit):
        name = raw_name.strip()
        if not name:
            continue
        if any(similarity(name, present) >= CREDIT_NAME_SIMILARITY for present in names):
            continue
        names.append(name)
    return names


def missing_credit_names(
    current_artist: str,
    current_title: str,
    proposed_artist: str,
    proposed_title: str,
) -> list[str]:
    """Return local credits absent from the complete proposed artist/title pair."""
    proposed_names = credit_names(proposed_artist, proposed_title)
    return [
        name
        for name in credit_names(current_artist, current_title)
        if not any(
            similarity(name, proposed) >= CREDIT_NAME_SIMILARITY
            for proposed in proposed_names
        )
    ]


def youtube_credit_metadata(url: str, timeout: int = 45) -> dict[str, str]:
    """Read structured track credits from a YouTube URL without downloading it."""
    if not re.match(r"^https?://(?:www\.|music\.)?(?:youtube\.com|youtu\.be)/", url, re.I):
        raise Unidentified("no supported YouTube purl")
    executable = shutil.which("yt-dlp")
    if executable is None:
        raise Unidentified("yt-dlp is unavailable")
    try:
        proc = subprocess.run(
            [
                executable,
                "--ignore-config",
                *ytdlp_auth_args(),
                "--no-playlist",
                "--skip-download",
                "--dump-single-json",
                "--no-warnings",
                url,
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise Unidentified("YouTube metadata lookup timed out") from exc
    except OSError as exc:
        raise Unidentified(f"YouTube metadata lookup failed: {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip() or f"yt-dlp exited {proc.returncode}"
        raise Unidentified(f"YouTube metadata lookup failed: {detail}")
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Unidentified("yt-dlp returned invalid metadata") from exc

    raw_artists = data.get("artists")
    artists: list[str] = []
    if isinstance(raw_artists, (list, tuple)):
        for value in raw_artists:
            name = str(value or "").strip()
            if name and not any(
                similarity(name, present) >= CREDIT_NAME_SIMILARITY
                for present in artists
            ):
                artists.append(name)
    artist = ", ".join(artists) or str(data.get("artist") or "").strip()
    title = str(data.get("track") or data.get("title") or "").strip()
    if not artist or not title:
        raise Unidentified("YouTube metadata has no structured artist/title")
    return {"artist": artist, "title": title}


def filename_credit_loss(path: Path, tags) -> list[str]:
    """Return credits in the filename that are absent from the current tags."""
    file_artist, file_title = parse_filename(path)
    if not file_artist or not file_title:
        return []
    return missing_credit_names(
        file_artist,
        file_title,
        existing(tags, "artist"),
        existing(tags, "title"),
    )


def recovered_youtube_artist(path: Path, tags) -> str:
    """Verify a file's YouTube purl and return its complete artist credit."""
    purl = existing(tags, "purl")
    if not purl:
        raise Unidentified("file has no YouTube purl")
    source = youtube_credit_metadata(purl)
    file_artist, file_title = parse_filename(path)
    reference_title = file_title or existing(tags, "title")
    if (
        not reference_title
        or title_similarity(source["title"], reference_title)
        < CREDIT_RECOVERY_TITLE_SIMILARITY
    ):
        raise Unidentified("YouTube purl title does not match the file")

    _, source_credit, _ = track_identity(source["artist"], source["title"])
    unverified = missing_credit_names(
        file_artist,
        file_title,
        source_credit,
        source["title"],
    )
    if unverified:
        raise Unidentified(
            "YouTube purl does not verify: " + ", ".join(unverified)
        )
    return source_credit


def search_variants(artist: str, title: str) -> list[tuple[str, str]]:
    """Search both common provider layouts for a featured credit."""
    cleaned = clean_title(title)
    base_title, combined_credit, _ = track_identity(artist, cleaned)
    variants = [(artist.strip(), cleaned), (combined_credit, base_title)]
    seen = set()
    unique = []
    for query_artist, query_title in variants:
        key = (query_artist.casefold(), query_title.casefold())
        if query_title and key not in seen:
            seen.add(key)
            unique.append((query_artist, query_title))
    return unique


def strip_feat(title: str) -> str:
    return split_featured_title(title)[0]


def drop_redundant_feat(title: str, artist: str) -> str:
    """YouTube Music credits featured artists in the artist field and again inside
    the official title. Drop the second copy only when the first already names
    them: on a plain upload the feat is the only record of the collaborator."""
    if not artist:
        return title

    def prune(match: re.Match) -> str:
        return "" if credit_contains(artist, match.group("who")) else match.group(0)

    tidied = BRACKETED_FEATURE.sub(prune, title)
    tidied = TRAILING_FEATURE.sub(prune, tidied)
    return re.sub(r"\s{2,}", " ", tidied).strip()


def escape_lucene(value: str) -> str:
    return re.sub(r'(["\\])', r"\\\1", value)


def mb_query(title: str, artist: str, phrase: bool, album: str = "") -> str:
    term = f'"{escape_lucene(title)}"' if phrase else escape_lucene(title)
    query = f"recording:{term}"
    if artist:
        query += f' AND artist:"{escape_lucene(artist)}"'
    if album:
        query += f' AND release:"{escape_lucene(album)}"'
    return query


def mb_search(query: str, limiter: RateLimiter) -> list[dict]:
    response = http_get(
        MUSICBRAINZ_ENDPOINT,
        {"query": query, "fmt": "json", "limit": 5},
        limiter,
    )
    return response.json().get("recordings") or []


SKIP_RELEASE_TYPES = {"compilation", "dj-mix", "mixtape/street", "live", "remix"}


def is_compilation(release: dict) -> bool:
    group = release.get("release-group") or {}
    secondary = {s.lower() for s in (group.get("secondary-types") or [])}
    return bool(secondary & SKIP_RELEASE_TYPES)


def pick_mb_release(releases: list[dict], album: str = "") -> dict:
    """Prefer the original release. A various-artists compilation is worse than no
    album at all: it groups unrelated tracks together in every player."""
    if not releases:
        return {}
    if album:
        releases = [
            release
            for release in releases
            if album_agrees(release.get("title", ""), album)
        ]
        if not releases:
            return {}

    def rank(release: dict) -> tuple:
        primary = ((release.get("release-group") or {}).get("primary-type") or "").lower()
        return (
            is_compilation(release),
            primary not in ("album", "single", "ep"),
            release.get("date") or "9999",
        )

    best = sorted(releases, key=rank)[0]
    return {} if is_compilation(best) and not album else best


def from_musicbrainz(
    artist: str,
    title: str,
    limiter: RateLimiter,
    album: str = "",
) -> dict:
    if not title:
        raise Unidentified("no title to search with")

    cleaned = clean_title(title)
    base_title, _, _ = track_identity(artist, cleaned)
    variants = [
        (title, True),
        (cleaned, True),
        (base_title, True),
        (cleaned, False),
        (base_title, False),
    ]

    seen: set[str] = set()
    for variant, phrase in variants:
        if not variant:
            continue
        query = mb_query(variant, artist, phrase, album)
        if query in seen:
            continue
        seen.add(query)

        for rec in mb_search(query, limiter):
            if rec.get("score", 0) < MUSICBRAINZ_MIN_SCORE:
                continue
            credit = rec.get("artist-credit") or []
            credited = ", ".join(c["artist"]["name"] for c in credit if c.get("artist"))
            mb_title = rec.get("title", "")
            if not candidate_agrees(credited, mb_title, artist, cleaned):
                continue
            # Skipped across scripts: a romanised filename scores ~0 against the original.
            mb_base, _, _ = track_identity("", mb_title)
            variant_base, _, _ = track_identity("", variant)
            if same_script(mb_base, variant_base) and (
                similarity(mb_base, variant_base) < MIN_TITLE_SIMILARITY
            ):
                continue
            release = pick_mb_release(rec.get("releases") or [], album)
            if album and not release:
                continue
            return {
                "title": rec.get("title", ""),
                "artist": credited,
                "albumartist": primary_artist("", credited),
                "album": release.get("title", ""),
                "date": (release.get("date") or "")[:4],
                "musicbrainz_trackid": rec.get("id", ""),
            }

    raise Unidentified("no musicbrainz match")


def jpeg_size(data: bytes) -> tuple[int, int]:
    """Width and height from the SOF segment. Players tolerate zeroes, but a
    correct picture block is cheap and PIL is not in the managed venv."""
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker, length = data[i + 1], int.from_bytes(data[i + 2:i + 4], "big")
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height = int.from_bytes(data[i + 5:i + 7], "big")
            width = int.from_bytes(data[i + 7:i + 9], "big")
            return width, height
        i += 2 + length
    return 0, 0


def has_artwork(path: Path, tags) -> bool:
    if path.suffix.lower() == ".flac":
        return bool(tags.pictures)
    if path.suffix.lower() == ".opus":
        return bool(tags.get("metadata_block_picture"))
    try:
        return any(k.startswith("APIC") for k in ID3(path).keys())
    except (ID3NoHeaderError, MutagenError):
        return False


def embedded_artwork(path: Path) -> bytes:
    """Return the first front-cover payload, independent of container format."""
    try:
        suffix = path.suffix.lower()
        if suffix == ".flac":
            pictures = FLAC(path).pictures
            return pictures[0].data if pictures else b""
        if suffix == ".opus":
            values = OggOpus(path).get("metadata_block_picture") or []
            if not values:
                return b""
            return Picture(base64.b64decode(values[0])).data
        pictures = ID3(path).getall("APIC")
        if not pictures:
            return b""
        front = next((picture for picture in pictures if picture.type == 3), pictures[0])
        return front.data
    except (ID3NoHeaderError, MutagenError, TypeError, ValueError):
        return b""


def embed_artwork(path: Path, data: bytes) -> None:
    width, height = jpeg_size(data)
    picture = Picture()
    picture.data, picture.type, picture.mime = data, 3, "image/jpeg"
    picture.width, picture.height, picture.depth = width, height, 24

    suffix = path.suffix.lower()
    if suffix == ".flac":
        audio = FLAC(path)
        audio.clear_pictures()
        audio.add_picture(picture)
        audio.save()
    elif suffix == ".opus":
        audio = OggOpus(path)
        audio["metadata_block_picture"] = [
            base64.b64encode(picture.write()).decode("ascii")
        ]
        audio.save()
    else:
        try:
            frames = ID3(path)
        except ID3NoHeaderError:
            frames = ID3()
        frames.delall("APIC")
        frames.add(APIC(encoding=3, mime="image/jpeg", type=3, desc="Cover", data=data))
        frames.save(path)


def write_tags(path: Path, meta: dict, force: bool, tags=None) -> dict:
    if tags is None:
        tags = read_tags(path)
    is_vorbis = path.suffix.lower() in VORBIS
    valid = None if is_vorbis else set(EasyID3.valid_keys.keys())

    written = {}
    for field, value in meta.items():
        if not value or field in NON_TAG_FIELDS:
            continue
        if valid is not None and field not in valid:
            continue
        if not force and existing(tags, field):
            continue
        tags[field.upper() if is_vorbis else field] = value
        written[field] = value

    if written:
        tags.save()
    return written


def prepare_metadata(
    tags,
    meta: dict,
    force: bool,
    allow_credit_loss: bool = False,
    path: Path | None = None,
) -> dict:
    """Apply output cleanup and prevent forced writes from narrowing credits."""
    prepared = dict(meta)
    if not prepared.get("title"):
        return prepared
    current_artist = existing(tags, "artist")
    current_title = existing(tags, "title")
    proposed_artist = prepared.get("artist", "") or current_artist
    proposed_title = prepared.get("title", "") or current_title

    local_candidates = [(current_artist, current_title)]
    if path is not None:
        file_artist, file_title = parse_filename(path)
        if file_artist and file_title and (
            not proposed_title
            or title_similarity(file_title, proposed_title) >= MIN_TITLE_SIMILARITY
        ):
            local_candidates.append((file_artist, file_title))

    if force and not allow_credit_loss:
        protected_artist = ""
        lost_names: list[str] = []
        for local_artist, local_title in local_candidates:
            missing = missing_credit_names(
                local_artist,
                local_title,
                proposed_artist,
                proposed_title,
            )
            if len(missing) > len(lost_names):
                _, protected_artist, _ = track_identity(local_artist, local_title)
                lost_names = missing
        if lost_names:
            prepared["artist"] = protected_artist
            prepared["_preserved_credits"] = ", ".join(lost_names)

    final_artist = prepared.get("artist", "") if force or not current_artist else current_artist
    prepared["title"] = drop_redundant_feat(prepared["title"], final_artist)
    return prepared


def tidy_title(path: Path, dry_run: bool, tags=None) -> str:
    """Needs no provider, so it also reaches files no lookup can identify — which
    is where the duplicated credit comes from. Keeps the tag in step with the name
    rename_from_tags derives from it."""
    if tags is None:
        tags = read_tags(path)
    title = existing(tags, "title")
    tidied = drop_redundant_feat(title, existing(tags, "artist"))
    if not tidied or tidied == title:
        return ""
    if not dry_run:
        tags["TITLE" if path.suffix.lower() in VORBIS else "title"] = tidied
        tags.save()
    return tidied


def split_leading_artist(title: str, artist: str) -> str:
    """YouTube titles repeat the artist ("Chidinma - Fallen in Love")."""
    if " - " not in title:
        return title
    left, _, right = title.partition(" - ")
    if right and (not artist or similarity(left, artist) >= 0.5):
        return right.strip()
    return title


# A bucket never names an artist: [G]'s children are artists, [C]'s are releases.
BUCKET_ARTISTS = re.compile(r"\s*\[g\]\s*$", re.I)
BUCKET_ALBUMS = re.compile(r"\s*\[c\]\s*$", re.I)


def bucket_index(parts: tuple[str, ...]) -> int:
    for i in range(len(parts) - 1, -1, -1):
        if BUCKET_ARTISTS.search(parts[i]) or BUCKET_ALBUMS.search(parts[i]):
            return i
    return -1


def folder_hints(path: Path, root: Path) -> tuple[str, str]:
    """One directory below the root names the artist; two or more name the album,
    with the artist directly above it. Below a bucket the same shape applies to
    whatever the bucket declares its children to be."""
    try:
        parts = path.relative_to(root).parts[:-1]
    except ValueError:
        return "", ""
    if not parts:
        return "", ""

    at = bucket_index(parts)
    if at >= 0:
        inner = parts[at + 1:]
        if not inner:
            return "", ""
        if BUCKET_ALBUMS.search(parts[at]):
            return "", inner[-1]
        return inner[0], (inner[-1] if len(inner) > 1 else "")

    if len(parts) == 1:
        return parts[0], ""
    return parts[-2], parts[-1]


def album_context(path: Path, tags, root: Path) -> tuple[str, tuple]:
    """Return the intended album and a stable grouping key.

    A library directory is authoritative over a per-track single/compilation tag.
    Existing tags remain the fallback for loose files and external scan roots.
    """
    dir_artist, dir_album = folder_hints(path, root)
    album = dir_album or existing(tags, "album")
    if not album:
        return "", ()
    owner = (
        dir_artist
        or existing(tags, "albumartist")
        or primary_artist("", existing(tags, "artist"))
    )
    return album, (tuple(normalize(owner)), tuple(normalize(album)))


def candidate_key(artist: str, title: str) -> tuple[tuple[str, ...], tuple[str, ...]]:
    base_title, combined_credit, _ = track_identity(artist, title)
    return (
        tuple(normalize(combined_credit)) or (combined_credit.casefold().strip(),),
        tuple(normalize(base_title)) or (base_title.casefold().strip(),),
    )


def derive_candidates(path: Path, tags, root: Path) -> list[tuple[str, str]]:
    """Filename first: for ripped video these tags hold the uploader and the full
    video title, while the filename is already "<artist> - <title>"."""
    file_artist, file_title = parse_filename(path)
    tag_artist = existing(tags, "artist")
    tag_title = existing(tags, "title")

    dir_artist, _ = folder_hints(path, root)

    candidates = []
    if file_artist and file_title:
        candidates.append((file_artist, file_title))
    if tag_title:
        candidates.append((tag_artist, split_leading_artist(tag_title, tag_artist)))
    if file_title and not file_artist:
        # A candidate with no artist skips the artist gate, so prefer the directory.
        if dir_artist:
            candidates.append((dir_artist, file_title))
        if tag_artist or not dir_artist:
            candidates.append((tag_artist, file_title))

    seen = set()
    unique = []
    for artist, title in candidates:
        keyed = candidate_key(artist, title)
        if title and keyed not in seen:
            seen.add(keyed)
            unique.append((artist.strip(), title.strip()))
    return unique


def first_artist_fallbacks(
    candidates: list[tuple[str, str]],
) -> list[tuple[str, str]]:
    """Keep the full identity authoritative, but provide a lean search identity
    when YouTube flattens performers, writers and producers into one artist list."""
    seen = {candidate_key(artist, title) for artist, title in candidates}
    fallbacks = []
    for artist, title in candidates:
        first_artist = primary_artist("", artist)
        keyed = candidate_key(first_artist, title)
        if first_artist and keyed not in seen:
            seen.add(keyed)
            fallbacks.append((first_artist, title))
    return fallbacks


def resolution_cache_key(
    path: Path,
    candidates: list[tuple[str, str]],
    fallback_candidates: list[tuple[str, str]],
    args,
    has_acoustid_key: bool,
    album: str = "",
) -> str:
    stat = path.stat()
    payload = {
        "version": CACHE_VERSION,
        "path": str(path.absolute()),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "candidates": candidates,
        "first_artist_fallbacks": fallback_candidates,
        "album": album,
        "acoustid": has_acoustid_key and not args.no_fingerprint,
        "min_score": args.min_score,
        "providers": args.provider_order,
        "fallback": args.fallback,
        "min_similarity": args.min_similarity,
    }
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


def resolve(
    path: Path,
    root: Path,
    args,
    limiters: dict,
    key: str,
    tags=None,
    cache: ResolutionCache | None = None,
    refresh_cache: bool = False,
) -> dict:
    if tags is None:
        tags = read_tags(path)
    candidates = derive_candidates(path, tags, root)
    fallback_candidates = first_artist_fallbacks(candidates)
    album, _ = album_context(path, tags, root)
    cache_key = (
        resolution_cache_key(
            path,
            candidates,
            fallback_candidates,
            args,
            bool(key),
            album,
        )
        if cache is not None
        else ""
    )
    if cache is not None and not refresh_cache:
        cached = cache.get(cache_key)
        if cached is not None:
            if cached.get("identified"):
                return cached.get("metadata") or {}
            raise Unidentified(f"{cached.get('reason', 'no match')} [cached]")

    def identified(metadata: dict) -> dict:
        if cache is not None:
            cache.put(
                cache_key,
                {"identified": True, "metadata": metadata},
                CACHE_SUCCESS_TTL,
            )
        return metadata

    if key and not args.no_fingerprint:
        try:
            return identified(
                from_acoustid(
                    path,
                    key,
                    limiters["acoustid"],
                    args.min_score,
                    candidates + (fallback_candidates if args.fallback else []),
                    album=album,
                )
            )
        except Unidentified as exc:
            if not args.fallback:
                if cache is not None:
                    cache.put(
                        cache_key,
                        {"identified": False, "reason": str(exc)},
                        CACHE_MISS_TTL,
                    )
                raise

    if not candidates:
        raise Unidentified("no title to search with")

    # Without an artist the gate cannot run and a generic title matches anything.
    candidates = [c for c in candidates if c[0]]
    if not candidates:
        raise Unidentified("no artist in filename, tags or parent folder")
    fallback_candidates = [c for c in fallback_candidates if c[0]]
    candidate_tiers = [candidates]
    if args.fallback and fallback_candidates:
        candidate_tiers.append(fallback_candidates)

    # Exhaust exact credits across every provider before relaxing to the first
    # artist. This keeps a broad iTunes result from beating an exact Deezer match.
    failures: dict[str, list[str]] = {}
    for tier_index, candidate_tier in enumerate(candidate_tiers):
        best_fallback = None
        best_fallback_score = 0.0
        for provider in args.provider_order:
            for artist, title in candidate_tier:
                try:
                    if provider == "itunes":
                        metadata = from_itunes(
                            artist,
                            title,
                            limiters["itunes"],
                            args.min_similarity,
                            album=album,
                        )
                    elif provider == "deezer":
                        metadata = from_deezer(
                            artist,
                            title,
                            limiters["deezer"],
                            args.min_similarity,
                            album=album,
                        )
                    else:
                        metadata = from_musicbrainz(
                            artist,
                            title,
                            limiters["musicbrainz"],
                            album=album,
                        )

                    if tier_index == 0:
                        return identified(metadata)

                    score = match_score(
                        metadata.get("artist", ""),
                        metadata.get("title", ""),
                        artist,
                        title,
                    )
                    if score > best_fallback_score:
                        best_fallback = metadata
                        best_fallback_score = score
                    if score >= 0.999:
                        return identified(metadata)
                except Unidentified as exc:
                    failures.setdefault(str(exc), []).append(provider)
            if not args.fallback:
                break
        if best_fallback is not None:
            return identified(best_fallback)

    tried_candidates = [
        candidate
        for candidate_tier in candidate_tiers
        for candidate in candidate_tier
    ]
    tried = " | ".join(
        f"{artist} - {title}" if artist else title
        for artist, title in tried_candidates
    )
    summary = "; ".join(
        f"{reason} ({', '.join(dict.fromkeys(providers))})"
        for reason, providers in failures.items()
    )
    reason = f"{summary} [tried: {tried}]"
    if cache is not None:
        cache.put(
            cache_key,
            {"identified": False, "reason": reason},
            CACHE_MISS_TTL,
        )
    raise Unidentified(reason)


def collect(paths: list[str], wanted: set[str]) -> list[tuple[Path, Path]]:
    """Pairs each file with the scan root it came from, which folder_hints needs to
    know how deep the file sits."""
    music = music_library_dir()
    found: list[tuple[Path, Path]] = []
    for raw in paths:
        path = Path(raw).expanduser()
        if path.is_dir():
            root = music if path.is_relative_to(music) else path
            found.extend(
                (p, root)
                for p in sorted(path.rglob("*"))
                if p.suffix.lower() in wanted and p.is_file()
            )
        elif path.suffix.lower() in wanted:
            root = music if path.is_relative_to(music) else path.parent
            found.append((path, root))
        elif path.suffix.lower() in SUPPORTED:
            print(f"skip (filtered by --ext): {path}", file=sys.stderr)
        else:
            print(f"skip (unsupported): {path}", file=sys.stderr)
    return found


def restore_youtube_credit_tags(
    files: list[tuple[Path, Path]],
    dry_run: bool,
) -> int:
    """Repair only ARTIST tags, using filenames as the local loss signal."""
    restored = complete = failed = 0
    for path, _root in files:
        try:
            tags = read_tags(path)
            lost_credits = filename_credit_loss(path, tags)
            if not lost_credits:
                complete += 1
                continue
            old_artist = existing(tags, "artist") or "(missing)"
            artist = recovered_youtube_artist(path, tags)
            if not dry_run:
                write_tags(path, {"artist": artist}, force=True, tags=tags)
        except Unidentified as exc:
            print(f"?? {path.name}: {exc}", file=sys.stderr)
            failed += 1
            continue
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: unreadable: {exc}", file=sys.stderr)
            failed += 1
            continue

        verb = "would restore" if dry_run else "restored"
        print(
            f"{verb} ARTIST: {path.name}\n"
            f"                {old_artist} -> {artist}",
            flush=True,
        )
        restored += 1

    restore_summary = "to restore" if dry_run else "restored"
    tag_word = "tag" if restored == 1 else "tags"
    print(
        f"\n{restored} ARTIST {tag_word} {restore_summary}, "
        f"{complete} already complete, {failed} failed"
        f"{'' if not dry_run else '  (dry run)'}"
    )
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Look up track metadata and write it into .mp3/.opus/.flac files"
    )
    parser.add_argument(
        "paths",
        nargs="*",
        metavar="PATH",
        help="Files or directories to tag (default: configured music library)",
    )
    parser.add_argument("-n", "--dry-run", action="store_true",
                        help="Report what would change without writing")
    parser.add_argument("-f", "--force", action="store_true",
                        help="Overwrite existing tags instead of only filling gaps")
    parser.add_argument(
        "--allow-credit-loss",
        action="store_true",
        help="Allow --force to replace a richer local artist credit with a narrower one",
    )
    parser.add_argument(
        "--restore-youtube-credits",
        action="store_true",
        help="Only repair ARTIST tags from verified YouTube purl metadata",
    )
    parser.add_argument("--no-fingerprint", action="store_true",
                        help="Skip AcoustID; match on existing tags or filename")
    parser.add_argument("--no-fallback", dest="fallback", action="store_false",
                        help="Fail instead of falling back to a MusicBrainz text search")
    parser.add_argument("--min-score", type=float, default=0.5,
                        help="Minimum AcoustID confidence (default: 0.5)")
    parser.add_argument("--provider", default=DEFAULT_PROVIDER_ORDER,
                        help="Comma-separated providers to try in order "
                             f"(default: {DEFAULT_PROVIDER_ORDER}); "
                             f"any of: {', '.join(PROVIDERS)}")
    parser.add_argument("--fill", default=",".join(FILL_FIELDS),
                        help="Only look a file up when one of these tags is missing "
                             f"(default: {','.join(FILL_FIELDS)})")
    parser.add_argument("--min-similarity", type=float, default=0.60,
                        help="Minimum artist/title similarity (default: 0.60)")
    parser.add_argument("--no-artwork", dest="artwork", action="store_false",
                        help="Skip embedding cover art from the provider")
    parser.add_argument(
        "--replace-artwork",
        action="store_true",
        help="Replace existing artwork; tracks in one album share one catalog cover",
    )
    cache_group = parser.add_mutually_exclusive_group()
    cache_group.add_argument(
        "--no-cache",
        action="store_true",
        help="Do not read or write the persistent lookup cache",
    )
    cache_group.add_argument(
        "--refresh-cache",
        action="store_true",
        help="Ignore cached lookups and replace them with fresh results",
    )
    parser.add_argument("--ext", default="",
                        help="Comma-separated extensions to include "
                             f"(default: {','.join(sorted(e[1:] for e in SUPPORTED))})")
    args = parser.parse_args()

    if args.provider == "auto":
        args.provider = DEFAULT_PROVIDER_ORDER
    args.provider_order = [p.strip().lower() for p in args.provider.split(",") if p.strip()]
    unknown = [p for p in args.provider_order if p not in PROVIDERS]
    if unknown or not args.provider_order:
        parser.error(f"unknown provider(s): {', '.join(unknown) or '(none given)'}")

    fill = [f.strip().lower() for f in args.fill.split(",") if f.strip()]
    unknown = [f for f in fill if f not in FILL_FIELDS]
    if unknown:
        parser.error(f"unknown --fill field(s): {', '.join(unknown)}")

    if args.ext:
        wanted = {"." + e.strip().lstrip(".").lower() for e in args.ext.split(",") if e.strip()}
        unknown = wanted - SUPPORTED
        if unknown:
            parser.error(f"unsupported extension(s): {', '.join(sorted(unknown))}")
    else:
        wanted = set(SUPPORTED)

    paths = args.paths or [str(music_library_dir())]
    files = collect(paths, wanted)
    if not files:
        print(f"no {'/'.join(sorted(wanted))} files found", file=sys.stderr)
        return 0

    if args.restore_youtube_credits:
        return restore_youtube_credit_tags(files, args.dry_run)

    key = acoustid_key()
    if not key and not args.no_fingerprint:
        print(
            "no AcoustID key (set ACOUSTID_API_KEY or "
            f"{config_home()}/acoustid/api.token); using text search",
            file=sys.stderr,
        )
    replace_artwork = args.force or args.replace_artwork
    lookup_key = "" if replace_artwork else key

    cache = None
    if not args.no_cache:
        try:
            cache = ResolutionCache(cache_home() / "hypr" / "autotag.sqlite3")
        except (OSError, sqlite3.Error) as exc:
            print(f"lookup cache unavailable: {exc}", file=sys.stderr)
    configure_persistent_cache(cache)

    limiters = {
        "acoustid": RateLimiter(ACOUSTID_INTERVAL),
        "musicbrainz": RateLimiter(MUSICBRAINZ_INTERVAL),
        "itunes": RateLimiter(ITUNES_INTERVAL),
        "deezer": RateLimiter(DEEZER_INTERVAL),
    }
    failed = 0

    complete = 0
    album_artwork_groups: dict[tuple, dict] = {}

    for path, root in files:
        try:
            tags = read_tags(path)
            album, album_key = album_context(path, tags, root)
            artwork_group = None
            if args.artwork and replace_artwork and album_key:
                artwork_group = album_artwork_groups.setdefault(
                    album_key,
                    {
                        "album": album,
                        "paths": [],
                        "roots": {},
                        "metadata": {},
                        "urls": [],
                    },
                )
                artwork_group["paths"].append(path)
                artwork_group["roots"][path] = root
            tidied = tidy_title(path, args.dry_run, tags)
            if tidied:
                verb = "would drop" if args.dry_run else "dropped"
                print(f".. {path.name}: {verb} duplicated credit -> {tidied!r}", flush=True)

            if (
                not replace_artwork
                and fill
                and all(existing(tags, field) for field in fill)
            ):
                complete += 1
                continue

            meta = resolve(
                path,
                root,
                args,
                limiters,
                lookup_key,
                tags,
                cache,
                args.refresh_cache,
            )
            meta = prepare_metadata(
                tags,
                meta,
                args.force,
                allow_credit_loss=args.allow_credit_loss,
                path=path,
            )
            if meta.get("_preserved_credits"):
                print(
                    f".. {path.name}: preserved local credit(s): "
                    f"{meta['_preserved_credits']}",
                    flush=True,
                )
            if artwork_group is not None:
                artwork_group["metadata"][path] = meta
            if (
                artwork_group is not None
                and meta.get("artwork_url")
                and album_agrees(meta.get("album", ""), album)
            ):
                artwork_group["urls"].append(meta["artwork_url"])

            if args.dry_run:
                changes = {
                    f: v for f, v in meta.items()
                    if (
                        f not in NON_TAG_FIELDS
                        and v
                        and (args.force or not existing(tags, f))
                    )
                }
                if (
                    artwork_group is None
                    and args.artwork
                    and meta.get("artwork_url")
                    and (replace_artwork or not has_artwork(path, tags))
                ):
                    changes["artwork"] = meta["artwork_url"].rsplit("/", 1)[-1]
                summary = ", ".join(f"{f}={v!r}" for f, v in changes.items()) or "nothing to change"
                print(f"-- {path.name}: {summary}", flush=True)
                continue

            written = write_tags(path, meta, args.force, tags)

            if (
                artwork_group is None
                and args.artwork
                and meta.get("artwork_url")
                and (replace_artwork or not has_artwork(path, tags))
            ):
                image = HTTP_SESSION.get(meta["artwork_url"], timeout=20)
                image.raise_for_status()
                if embedded_artwork(path) != image.content:
                    embed_artwork(path, image.content)
                    written["artwork"] = f"{len(image.content) // 1024}KB"

            # Tag/artwork writes change the file signature used by the cache.
            # Alias the same result under the new signature for the next scan.
            if cache is not None and written:
                cache_resolution(
                    cache,
                    path,
                    root,
                    tags,
                    args,
                    bool(lookup_key),
                    meta,
                )
        except Unidentified as exc:
            print(f"?? {path.name}: {exc}", file=sys.stderr)
            failed += 1
            continue
        except requests.RequestException as exc:
            print(f"!! {path.name}: lookup failed: {exc}", file=sys.stderr)
            failed += 1
            continue
        except (MutagenError, OSError) as exc:
            print(f"!! {path.name}: unreadable: {exc}", file=sys.stderr)
            failed += 1
            continue

        identity = f"{meta.get('artist') or '?'} - {meta.get('title') or '?'}"
        if written:
            print(f"OK {path.name}: {identity} [{', '.join(sorted(written))}]", flush=True)
        else:
            print(f"== {path.name}: {identity} (already tagged)", flush=True)

    if args.artwork and replace_artwork:
        for group in album_artwork_groups.values():
            if not group["urls"]:
                continue
            artwork_url = Counter(group["urls"]).most_common(1)[0][0]
            paths = group["paths"]
            if args.dry_run:
                name = artwork_url.rsplit("/", 1)[-1]
                print(
                    f"-- {group['album']}: artwork={name!r} for {len(paths)} file(s)",
                    flush=True,
                )
                continue
            try:
                image = HTTP_SESSION.get(artwork_url, timeout=20)
                image.raise_for_status()
            except requests.RequestException as exc:
                print(
                    f"!! {group['album']}: artwork download failed: {exc}",
                    file=sys.stderr,
                )
                failed += 1
                continue
            updated = 0
            unchanged = 0
            for path in paths:
                try:
                    if embedded_artwork(path) == image.content:
                        unchanged += 1
                    else:
                        embed_artwork(path, image.content)
                        updated += 1
                    metadata = group["metadata"].get(path)
                    if metadata is not None:
                        tags = read_tags(path)
                        cache_resolution(
                            cache,
                            path,
                            group["roots"][path],
                            tags,
                            args,
                            bool(lookup_key),
                            metadata,
                        )
                except (MutagenError, OSError) as exc:
                    print(f"!! {path.name}: artwork failed: {exc}", file=sys.stderr)
                    failed += 1
            print(
                f"ART {group['album']}: one cover -> "
                f"{updated} updated, {unchanged} already correct",
                flush=True,
            )

    if complete:
        print(f"\nskipped {complete} file(s) already carrying every --fill tag", file=sys.stderr)
    if cache is not None:
        if cache.hits:
            print(f"reused {cache.hits} cached lookup(s)", file=sys.stderr)
        configure_persistent_cache(None)
        cache.close()
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
