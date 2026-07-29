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
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path

import requests
from mutagen import MutagenError
from mutagen.easyid3 import EasyID3
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3, ID3NoHeaderError
from mutagen.mp3 import MP3
from mutagen.oggopus import OggOpus

ACOUSTID_ENDPOINT = "https://api.acoustid.org/v2/lookup"
MUSICBRAINZ_ENDPOINT = "https://musicbrainz.org/ws/2/recording"
ITUNES_ENDPOINT = "https://itunes.apple.com/search"
DEEZER_ENDPOINT = "https://api.deezer.com/search"
DEEZER_TRACK_ENDPOINT = "https://api.deezer.com/track"
CONTACT = os.environ.get("AUTOTAG_CONTACT", "hyprshell-autotag")
USER_AGENT = f"hyprshell-autotag/1.0 ( {CONTACT} )"

# MusicBrainz allows one request per second per client and blocks abusers.
MUSICBRAINZ_INTERVAL = 1.1
ACOUSTID_INTERVAL = 0.34
# Apple publishes no firm figure; the 429 backoff absorbs whatever the real one is.
ITUNES_INTERVAL = 1.2
DEEZER_INTERVAL = 0.2

# MusicBrainz scores matches 0-100; below this a hit is usually a different song.
MUSICBRAINZ_MIN_SCORE = 90

# Independent of the weighted score. Measured: worst true 0.51, best false 0.44.
# Not raisable to 0.60: correct pairs like "ru. & Magixx"/"ru." also score 0.50.
MIN_TITLE_SIMILARITY = 0.50
MIN_ARTIST_SIMILARITY = 0.50

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
NON_TAG_FIELDS = {"artwork_url"}

SUPPORTED = {".mp3", ".opus", ".flac"}
# Opus and FLAC both carry Vorbis comments, which are conventionally uppercase.
VORBIS = {".opus", ".flac"}
FIELDS = ("title", "artist", "album", "albumartist", "tracknumber", "date")


class Unidentified(Exception):
    pass


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))


def acoustid_key() -> str:
    key = os.environ.get("ACOUSTID_API_KEY", "").strip()
    if key:
        return key
    token_file = config_home() / "acoustid" / "api.token"
    if token_file.is_file():
        return token_file.read_text(encoding="utf-8").strip()
    return ""


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
        response = requests.get(
            url, params=params, headers={"User-Agent": USER_AGENT}, timeout=20
        )
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


def pick_release(recording: dict) -> dict:
    """Prefer an album over singles/compilations, then the earliest release."""
    groups = recording.get("releasegroups") or []
    if not groups:
        return {}
    albums = [g for g in groups if (g.get("type") or "").lower() == "album"]
    return (albums or groups)[0]


def from_acoustid(path: Path, key: str, limiter: RateLimiter, min_score: float) -> dict:
    duration, fp = fingerprint(path)
    response = http_get(
        ACOUSTID_ENDPOINT,
        {
            "client": key,
            "duration": duration,
            "fingerprint": fp,
            "meta": "recordings+releasegroups+compress",
        },
        limiter,
    )
    payload = response.json()
    if payload.get("status") != "ok":
        raise Unidentified(f"acoustid: {payload.get('error', {}).get('message', 'error')}")

    for result in sorted(payload.get("results", []), key=lambda r: r.get("score", 0), reverse=True):
        if result.get("score", 0) < min_score:
            break
        for recording in result.get("recordings") or []:
            if not recording.get("title"):
                continue
            artists = recording.get("artists") or []
            group = pick_release(recording)
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


def match_score(cand_artist: str, cand_title: str, artist: str, title: str) -> float:
    title_score = similarity(cand_title, title)
    if not artist:
        return title_score
    return 0.6 * title_score + 0.4 * similarity(cand_artist, artist)


def strip_release_suffix(album: str) -> str:
    return re.sub(r"\s*-\s*(?:Single|EP)\s*$", "", album, flags=re.I).strip()


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


def from_itunes(artist: str, title: str, limiter: RateLimiter, threshold: float) -> dict:
    if not title:
        raise Unidentified("no title to search with")

    cleaned = clean_title(title)
    term = f"{artist} {cleaned}".strip()
    response = http_get(
        ITUNES_ENDPOINT,
        {"term": term, "media": "music", "entity": "song", "limit": 10},
        limiter,
    )
    results = response.json().get("results") or []
    if not results:
        raise Unidentified("no itunes match")

    best = None
    best_score = 0.0
    best_solo = None
    best_solo_score = 0.0
    rejected = 0.0
    for item in results:
        cand_artist = item.get("artistName", "")
        cand_title = item.get("trackName", "")
        score = match_score(cand_artist, cand_title, artist, cleaned)
        if similarity(cand_title, cleaned) < MIN_TITLE_SIMILARITY:
            rejected = max(rejected, score)
            continue
        if not artist_agrees(cand_artist, artist):
            rejected = max(rejected, score)
            continue
        if score > best_score:
            best, best_score = item, score
        if not itunes_is_compilation(item) and score > best_solo_score:
            best_solo, best_solo_score = item, score

    # A DJ mix's album and track number describe the mix, not the song. Only trade
    # down to one if the artist still agrees at least as well: the right song on a
    # mix beats the wrong artist on a studio release.
    if best_solo is not None and best_solo_score >= threshold and artist:
        if similarity(best_solo.get("artistName", ""), artist) < similarity(
            best.get("artistName", ""), artist
        ):
            best_solo = None
    if best_solo is not None and best_solo_score >= threshold:
        best, best_score = best_solo, best_solo_score

    if best is None or best_score < threshold:
        detail = f"{best_score:.2f}"
        if best is None and rejected:
            detail = f"{rejected:.2f}, failed title/artist gate"
        raise Unidentified(f"itunes best match too weak ({detail})")

    compilation = itunes_is_compilation(best)
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


def from_deezer(artist: str, title: str, limiter: RateLimiter, threshold: float) -> dict:
    if not title:
        raise Unidentified("no title to search with")

    cleaned = clean_title(title)
    response = http_get(DEEZER_ENDPOINT, {"q": f"{artist} {cleaned}".strip()}, limiter)
    results = response.json().get("data") or []
    if not results:
        raise Unidentified("no deezer match")

    best = None
    best_score = 0.0
    rejected = 0.0
    for item in results:
        cand_artist = (item.get("artist") or {}).get("name", "")
        cand_title = item.get("title", "")
        score = match_score(cand_artist, cand_title, artist, cleaned)
        if similarity(cand_title, cleaned) < MIN_TITLE_SIMILARITY:
            rejected = max(rejected, score)
            continue
        if not artist_agrees(cand_artist, artist):
            rejected = max(rejected, score)
            continue
        if score > best_score:
            best, best_score = item, score

    if best is None or best_score < threshold:
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


def strip_feat(title: str) -> str:
    return re.sub(r"\s*[\(\[]?\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]*[\)\]]?\s*$",
                  "", title, flags=re.I).strip()


def escape_lucene(value: str) -> str:
    return re.sub(r'(["\\])', r"\\\1", value)


def mb_query(title: str, artist: str, phrase: bool) -> str:
    term = f'"{escape_lucene(title)}"' if phrase else escape_lucene(title)
    query = f"recording:{term}"
    if artist:
        query += f' AND artist:"{escape_lucene(artist)}"'
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


def pick_mb_release(releases: list[dict]) -> dict:
    """Prefer the original release. A various-artists compilation is worse than no
    album at all: it groups unrelated tracks together in every player."""
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
    return {} if is_compilation(best) else best


def from_musicbrainz(artist: str, title: str, limiter: RateLimiter) -> dict:
    if not title:
        raise Unidentified("no title to search with")

    cleaned = clean_title(title)
    variants = [
        (title, True),
        (cleaned, True),
        (strip_feat(cleaned), True),
        (cleaned, False),
    ]

    seen: set[str] = set()
    for variant, phrase in variants:
        if not variant:
            continue
        query = mb_query(variant, artist, phrase)
        if query in seen:
            continue
        seen.add(query)

        for rec in mb_search(query, limiter):
            if rec.get("score", 0) < MUSICBRAINZ_MIN_SCORE:
                continue
            credit = rec.get("artist-credit") or []
            credited = ", ".join(c["artist"]["name"] for c in credit if c.get("artist"))
            if not artist_agrees(credited, artist):
                continue
            # Skipped across scripts: a romanised filename scores ~0 against the original.
            mb_title = rec.get("title", "")
            if same_script(mb_title, variant) and (
                similarity(mb_title, variant) < MIN_TITLE_SIMILARITY
            ):
                continue
            release = pick_mb_release(rec.get("releases") or [])
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


def embed_artwork(path: Path, data: bytes) -> None:
    width, height = jpeg_size(data)
    picture = Picture()
    picture.data, picture.type, picture.mime = data, 3, "image/jpeg"
    picture.width, picture.height, picture.depth = width, height, 24

    suffix = path.suffix.lower()
    if suffix == ".flac":
        audio = FLAC(path)
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
        frames.add(APIC(encoding=3, mime="image/jpeg", type=3, desc="Cover", data=data))
        frames.save(path)


def write_tags(path: Path, meta: dict, force: bool) -> dict:
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
        keyed = (artist.lower().strip(), title.lower().strip())
        if title and keyed not in seen:
            seen.add(keyed)
            unique.append((artist.strip(), title.strip()))
    return unique


def resolve(path: Path, root: Path, args, limiters: dict, key: str) -> dict:
    if key and not args.no_fingerprint:
        try:
            return from_acoustid(path, key, limiters["acoustid"], args.min_score)
        except Unidentified:
            if not args.fallback:
                raise

    candidates = derive_candidates(path, read_tags(path), root)
    if not candidates:
        raise Unidentified("no title to search with")

    # Without an artist the gate cannot run and a generic title matches anything.
    candidates = [c for c in candidates if c[0]]
    if not candidates:
        raise Unidentified("no artist in filename, tags or parent folder")

    reasons = []
    order = args.provider_order
    for provider in order:
        for artist, title in candidates:
            try:
                if provider == "itunes":
                    return from_itunes(artist, title, limiters["itunes"], args.min_similarity)
                if provider == "deezer":
                    return from_deezer(artist, title, limiters["deezer"], args.min_similarity)
                return from_musicbrainz(artist, title, limiters["musicbrainz"])
            except Unidentified as exc:
                reasons.append(f"{provider}[{title[:24]}]: {exc}")
        if not args.fallback:
            break
    raise Unidentified("; ".join(reasons))


def collect(paths: list[str], wanted: set[str]) -> list[tuple[Path, Path]]:
    """Pairs each file with the scan root it came from, which folder_hints needs to
    know how deep the file sits."""
    music = Path.home() / "Music"
    found: list[tuple[Path, Path]] = []
    for raw in paths:
        path = Path(raw).expanduser()
        if path.is_dir():
            found.extend(
                (p, path)
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


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Look up track metadata and write it into .mp3/.opus/.flac files"
    )
    parser.add_argument("paths", nargs="+", help="Files or directories to tag")
    parser.add_argument("-n", "--dry-run", action="store_true",
                        help="Report what would change without writing")
    parser.add_argument("-f", "--force", action="store_true",
                        help="Overwrite existing tags instead of only filling gaps")
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

    files = collect(args.paths, wanted)
    if not files:
        print(f"no {'/'.join(sorted(wanted))} files found", file=sys.stderr)
        return 0

    key = acoustid_key()
    if not key and not args.no_fingerprint:
        print(
            "no AcoustID key (set ACOUSTID_API_KEY or "
            f"{config_home()}/acoustid/api.token); using text search",
            file=sys.stderr,
        )

    limiters = {
        "acoustid": RateLimiter(ACOUSTID_INTERVAL),
        "musicbrainz": RateLimiter(MUSICBRAINZ_INTERVAL),
        "itunes": RateLimiter(ITUNES_INTERVAL),
        "deezer": RateLimiter(DEEZER_INTERVAL),
    }
    failed = 0

    complete = 0

    for path, root in files:
        try:
            if not args.force and fill:
                tags = read_tags(path)
                if all(existing(tags, field) for field in fill):
                    complete += 1
                    continue

            meta = resolve(path, root, args, limiters, key)

            if args.dry_run:
                tags = read_tags(path)
                changes = {
                    f: v for f, v in meta.items()
                    if v and (args.force or not existing(tags, f))
                }
                if args.artwork and meta.get("artwork_url") and (
                    args.force or not has_artwork(path, tags)
                ):
                    changes["artwork"] = meta["artwork_url"].rsplit("/", 1)[-1]
                summary = ", ".join(f"{f}={v!r}" for f, v in changes.items()) or "nothing to change"
                print(f"-- {path.name}: {summary}", flush=True)
                continue

            written = write_tags(path, meta, args.force)

            if args.artwork and meta.get("artwork_url"):
                tags = read_tags(path)
                if args.force or not has_artwork(path, tags):
                    image = requests.get(meta["artwork_url"], timeout=20)
                    image.raise_for_status()
                    embed_artwork(path, image.content)
                    written["artwork"] = f"{len(image.content) // 1024}KB"
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

    if complete:
        print(f"\nskipped {complete} file(s) already carrying every --fill tag", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
