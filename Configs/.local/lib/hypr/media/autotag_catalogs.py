from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils.xdg_base_dirs import xdg_config_home
from typing import NamedTuple
import requests
from autotag_identity import MIN_ARTIST_SIMILARITY, MIN_TITLE_SIMILARITY, album_agrees, album_similarity, artist_agrees, candidate_agrees, credit_similarity, match_score, primary_artist, search_variants, same_script, similarity, strip_release_suffix, title_similarity, track_identity
from title_cleanup import clean_title
from autotag_models import TrackTags, Unidentified
from autotag_cache import ResolutionCache


HTTP_TIMEOUT_S = 20


EXACT_MATCH_SCORE = 0.999


ACOUSTID_ENDPOINT = "https://api.acoustid.org/v2/lookup"


MUSICBRAINZ_ENDPOINT = "https://musicbrainz.org/ws/2/recording"


ITUNES_ENDPOINT = "https://itunes.apple.com/search"


ITUNES_RESULT_LIMIT = 25


MUSICBRAINZ_RESULT_LIMIT = 5


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


DEEZER_COOLDOWN = 60 * 60


# MusicBrainz scores matches 0-100; below this a hit is usually a different song.
MUSICBRAINZ_MIN_SCORE = 90


# iTunes serves any size by substituting into the URL; 600px is ~85KB against
# 231KB for 1000px, matching what yt-dlp embeds for new downloads.
ARTWORK_SIZE = "600x600bb.jpg"


# Set once Deezer 403s, so the rest of the run skips it instead of paying a
# request each time to be refused.
DEEZER_REFUSED = "deezer refused this address (403)"


DEEZER_BLOCKED_STATE = "deezer_blocked"


LATEST_POSSIBLE_DATE = "9999"


_deezer_blocked = False


_persistent_cache = None


def _disable_deezer() -> None:
    global _deezer_blocked
    if not _deezer_blocked:
        _deezer_blocked = True
        if _persistent_cache is not None:
            _persistent_cache.put_state(DEEZER_BLOCKED_STATE, DEEZER_COOLDOWN)
        print("deezer refused this address; skipping it for the rest of the run",
              file=sys.stderr)


def acoustid_key() -> str:
    key = os.environ.get("ACOUSTID_API_KEY", "").strip()
    if key:
        return key
    token_file = xdg_config_home() / "acoustid" / "api.token"
    if token_file.is_file():
        return token_file.read_text(encoding="utf-8").strip()
    return ""


def configure_persistent_cache(cache: ResolutionCache | None) -> None:
    global _deezer_blocked, _persistent_cache
    _persistent_cache = cache
    _deezer_blocked = bool(cache and cache.state_active(DEEZER_BLOCKED_STATE))


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
        response = HTTP_SESSION.get(url, params=params, timeout=HTTP_TIMEOUT_S)
        if response.status_code in (429, 503) and attempt < attempts - 1:
            retry_after = response.headers.get("Retry-After", "")
            time.sleep(float(retry_after) if retry_after.isdigit() else delay)
            delay *= 2
            continue
        break
    response.raise_for_status()
    return response


def fingerprint(path: Path) -> tuple[int, str]:
    process = subprocess.run(
        ["fpcalc", "-json", str(path)],
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        raise Unidentified(f"fpcalc failed: {process.stderr.strip()}")
    fingerprint_data = json.loads(process.stdout)
    return int(fingerprint_data["duration"]), fingerprint_data["fingerprint"]


def pick_release(recording: dict, album: str = "") -> dict:
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


def joined_names(people: list[dict]) -> str:
    return ", ".join(person["name"] for person in people if person.get("name"))


def acoustid_results(path: Path, key: str, limiter: RateLimiter) -> list[dict]:
    duration, fingerprint_data = fingerprint(path)
    response = http_get(
        ACOUSTID_ENDPOINT,
        {
            "client": key,
            "duration": duration,
            "fingerprint": fingerprint_data,
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
    return payload.get("results", [])


def rank_recordings_by_candidates(
    recordings: list[dict], candidates: list[tuple[str, str]]
) -> list[dict]:
    ranked = []
    for recording in recordings:
        credited = joined_names(recording.get("artists") or [])
        agreements = []
        for artist, title in candidates:
            _, wanted_credit, _ = track_identity(artist, title)
            if (
                title_similarity(recording["title"], title) >= MIN_TITLE_SIMILARITY
                and artist_agrees(credited, wanted_credit)
            ):
                agreements.append(match_score(credited, recording["title"], artist, title))
        if agreements:
            ranked.append((max(agreements), recording))
    return [recording for _, recording in sorted(ranked, key=lambda item: item[0], reverse=True)]


def acoustid_tags(recording: dict, group: dict) -> TrackTags:
    return {
        "title": recording["title"],
        "artist": joined_names(recording.get("artists") or []),
        "album": group.get("title", ""),
        "albumartist": joined_names(group.get("artists") or []),
        "musicbrainz_trackid": recording.get("id", ""),
        "musicbrainz_releasegroupid": group.get("id", ""),
    }


def from_acoustid(
    path: Path,
    key: str,
    limiter: RateLimiter,
    min_score: float,
    candidates: list[tuple[str, str]] | None = None,
    album: str = "",
) -> TrackTags:
    results = acoustid_results(path, key, limiter)
    for result in sorted(results, key=lambda r: r.get("score", 0), reverse=True):
        if result.get("score", 0) < min_score:
            break
        recordings = [r for r in result.get("recordings") or [] if r.get("title")]
        if candidates:
            recordings = rank_recordings_by_candidates(recordings, candidates)
        for recording in recordings:
            group = pick_release(recording, album)
            if album and not group:
                continue
            return acoustid_tags(recording, group)
    raise Unidentified("no acoustid match above threshold")


ITUNES_COMPILATION = re.compile(
    r"\((?:dj\s+mix|mixed)\)|\bgreatest\s+hits\b|\bcompilation\b|\bnow\s+that'?s\b", re.I
)


def itunes_is_compilation(item: dict) -> bool:
    """A collection credited to someone other than the track's artist is a
    various-artists release, not the single it came from."""
    if ITUNES_COMPILATION.search(item.get("collectionName") or ""):
        return True
    collection_artist = item.get("collectionArtistName") or ""
    return bool(collection_artist) and (
        similarity(collection_artist, item.get("artistName", "")) < MIN_ARTIST_SIMILARITY
    )


class ItunesRanking(NamedTuple):
    best: dict | None
    best_score: float
    solo: dict | None
    solo_score: float
    album_match: dict | None
    album_rank: tuple[float, float]
    rejected_score: float


def itunes_search(artist: str, title: str, limiter: RateLimiter) -> list[dict]:
    results = []
    seen_results = set()
    for query_artist, query_title in search_variants(artist, title):
        response = http_get(
            ITUNES_ENDPOINT,
            {
                "term": f"{query_artist} {query_title}".strip(),
                "media": "music",
                "entity": "song",
                "limit": ITUNES_RESULT_LIMIT,
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
    return results


def rank_itunes_results(results: list[dict], artist: str, title: str, album: str) -> ItunesRanking:
    best = solo = album_match = None
    best_score = solo_score = rejected_score = 0.0
    album_rank = (0.0, 0.0)
    for item in results:
        cand_artist = item.get("artistName", "")
        cand_title = item.get("trackName", "")
        score = match_score(cand_artist, cand_title, artist, title)
        if not candidate_agrees(cand_artist, cand_title, artist, title):
            rejected_score = max(rejected_score, score)
            continue
        if score > best_score:
            best, best_score = item, score
        if not itunes_is_compilation(item) and score > solo_score:
            solo, solo_score = item, score
        candidate_album = item.get("collectionName", "")
        if album_agrees(candidate_album, album):
            rank = (album_similarity(candidate_album, album), score)
            if rank > album_rank:
                album_match, album_rank = item, rank
    return ItunesRanking(best, best_score, solo, solo_score, album_match, album_rank, rejected_score)


def release_year(date: str | None) -> str:
    return (date or "")[:len("YYYY")]


def itunes_credit_similarity(item: dict, artist: str, title: str) -> float:
    return credit_similarity(item.get("artistName", ""), item.get("trackName", ""), artist, title)


def choose_itunes_match(
    ranking: ItunesRanking, artist: str, title: str, album: str, threshold: float
) -> dict:
    best, best_score = ranking.best, ranking.best_score
    # A DJ mix's album and track number describe the mix, not the song. Only trade
    # down to one if the artist still agrees at least as well: the right song on a
    # mix beats the wrong artist on a studio release.
    if album:
        if ranking.album_match is None or ranking.album_rank[1] < threshold:
            raise Unidentified("no itunes match on requested album")
        best, best_score = ranking.album_match, ranking.album_rank[1]
    elif (
        ranking.solo is not None
        and ranking.solo_score >= threshold
        and not (
            artist
            and itunes_credit_similarity(ranking.solo, artist, title)
            < itunes_credit_similarity(best, artist, title)
        )
    ):
        best, best_score = ranking.solo, ranking.solo_score

    if best is None or best_score < threshold:
        detail = f"{best_score:.2f}"
        if best is None and ranking.rejected_score:
            detail = f"{ranking.rejected_score:.2f}, failed title/artist gate"
        raise Unidentified(f"itunes best match too weak ({detail})")
    return best


def itunes_tags(match: dict, album: str) -> TrackTags:
    # A matching album hint makes an intentional DJ mix/compilation safe. Without
    # one, keep its grouping metadata out of a standalone track.
    compilation = itunes_is_compilation(match) and not album
    track_no = ""
    if match.get("trackNumber") and not compilation:
        track_no = str(match["trackNumber"])
        if match.get("trackCount"):
            track_no += f"/{match['trackCount']}"

    return {
        "title": match.get("trackName", ""),
        "artist": match.get("artistName", ""),
        "albumartist": "" if compilation else primary_artist(
            match.get("collectionArtistName") or "", match.get("artistName", "")
        ),
        "album": "" if compilation else strip_release_suffix(match.get("collectionName", "")),
        "date": "" if compilation else release_year(match.get("releaseDate")),
        "tracknumber": track_no,
        "genre": match.get("primaryGenreName", ""),
        "artwork_url": (match.get("artworkUrl100") or "").replace(
            "100x100bb.jpg", ARTWORK_SIZE
        ),
    }


def from_itunes(
    artist: str,
    title: str,
    limiter: RateLimiter,
    threshold: float,
    album: str = "",
) -> TrackTags:
    if not title:
        raise Unidentified("no title to search with")
    cleaned = clean_title(title)
    results = itunes_search(artist, cleaned, limiter)
    ranking = rank_itunes_results(results, artist, cleaned, album)
    match = choose_itunes_match(ranking, artist, cleaned, album, threshold)
    return itunes_tags(match, album)


def deezer_search(artist: str, title: str, limiter: RateLimiter) -> list[dict]:
    results = []
    seen_results = set()
    try:
        for query_artist, query_title in search_variants(artist, title):
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
    return results


def choose_deezer_match(
    results: list[dict], artist: str, title: str, album: str, threshold: float
) -> dict:
    best = None
    best_score = 0.0
    best_rank = (0.0, 0.0)
    rejected = 0.0
    for item in results:
        cand_artist = (item.get("artist") or {}).get("name", "")
        cand_title = item.get("title", "")
        score = match_score(cand_artist, cand_title, artist, title)
        if not candidate_agrees(cand_artist, cand_title, artist, title):
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
    return best


def deezer_tags(match: dict, limiter: RateLimiter) -> TrackTags:
    deezer_artist = (match.get("artist") or {}).get("name", "")
    meta = {
        "title": match.get("title", ""),
        "artist": deezer_artist,
        "albumartist": primary_artist("", deezer_artist),
        "album": strip_release_suffix((match.get("album") or {}).get("title", "")),
        "artwork_url": (match.get("album") or {}).get("cover_big", ""),
    }

    # Search hits omit the release date and track position; the track resource has them.
    if match.get("id"):
        try:
            detail = http_get(f"{DEEZER_TRACK_ENDPOINT}/{match['id']}", {}, limiter).json()
            meta["date"] = release_year(detail.get("release_date"))
            if detail.get("track_position"):
                meta["tracknumber"] = str(detail["track_position"])
        except requests.RequestException:
            pass
    return meta


def from_deezer(
    artist: str,
    title: str,
    limiter: RateLimiter,
    threshold: float,
    album: str = "",
) -> TrackTags:
    if not title:
        raise Unidentified("no title to search with")
    if _deezer_blocked:
        raise Unidentified(DEEZER_REFUSED)
    cleaned = clean_title(title)
    results = deezer_search(artist, cleaned, limiter)
    match = choose_deezer_match(results, artist, cleaned, album, threshold)
    return deezer_tags(match, limiter)


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
        {"query": query, "fmt": "json", "limit": MUSICBRAINZ_RESULT_LIMIT},
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
            release.get("date") or LATEST_POSSIBLE_DATE,
        )

    best = sorted(releases, key=rank)[0]
    return {} if is_compilation(best) and not album else best


def from_musicbrainz(
    artist: str,
    title: str,
    limiter: RateLimiter,
    album: str = "",
) -> TrackTags:
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
                "date": release_year(release.get("date")),
                "musicbrainz_trackid": rec.get("id", ""),
            }

    raise Unidentified("no musicbrainz match")

