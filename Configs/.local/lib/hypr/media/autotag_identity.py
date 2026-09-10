"""Track identity, similarity, and filesystem-derived lookup candidates."""

from __future__ import annotations

import re
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path
from typing import NamedTuple

from title_cleanup import clean_title

# Independent of the weighted score. Measured: worst true 0.51, best false 0.44.
# Correct pairs such as "ru. & Magixx"/"ru." prevent raising this to 0.60.
MIN_TITLE_SIMILARITY = 0.50
MIN_ARTIST_SIMILARITY = 0.50
MIN_ALBUM_SIMILARITY = 0.60
CREDIT_NAME_SIMILARITY = 0.90
CREDIT_RECOVERY_TITLE_SIMILARITY = 0.80

BRACKETED_FEATURE = re.compile(
    r"\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s+"
    r"(?P<who>[^)\]]+?)\s*[\)\]]",
    re.IGNORECASE,
)
TRAILING_FEATURE = re.compile(
    r"\s+(?:feat\.?|ft\.?|featuring)\s+(?P<who>.+?)\s*$", re.IGNORECASE
)
CREDIT_SEPARATOR = re.compile(
    r"\s*(?:,|&|;|\bfeat(?:uring)?\b\.?|\bft\b\.?|\bwith\b)\s*",
    re.IGNORECASE,
)
BUCKET_ARTISTS = re.compile(r"\s*\[g\]\s*$", re.IGNORECASE)
BUCKET_ALBUMS = re.compile(r"\s*\[c\]\s*$", re.IGNORECASE)


class TrackIdentity(NamedTuple):
    title: str
    credit: str
    featured_credit: str


def parse_filename(path: Path) -> tuple[str, str]:
    """Best-effort '<artist> - <title>' split, with track numbers stripped."""
    stem = re.sub(r"^\s*\d{1,3}\s*[-._)]\s*", "", path.stem)
    if " - " not in stem:
        return "", stem.strip()
    artist, _, title = stem.partition(" - ")
    return artist.strip(), title.strip()


def existing(tags, key: str) -> str:
    value = tags.get(key) or tags.get(key.upper())
    if not value:
        return ""
    return str(value[0] if isinstance(value, list) else value).strip()


def normalize(value: str) -> list[str]:
    folded = unicodedata.normalize("NFKD", value.lower())
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    folded = re.sub(r"\b(?:feat|ft|featuring|with)\b", " ", folded)
    return re.sub(r"[^0-9a-z]+", " ", folded).split()


def similarity(left: str, right: str) -> float:
    """Compare normalized token overlap and sequence order."""
    left_tokens, right_tokens = normalize(left), normalize(right)
    if not left_tokens or not right_tokens:
        return 0.0
    left_set, right_set = set(left_tokens), set(right_tokens)
    overlap = len(left_set & right_set) / len(left_set | right_set)
    sequence = SequenceMatcher(
        None, " ".join(left_tokens), " ".join(right_tokens)
    ).ratio()
    return max(overlap, sequence)


def has_non_latin(text: str) -> bool:
    return any(character.isalpha() and ord(character) > 0x24F for character in text)


def same_script(left: str, right: str) -> bool:
    return has_non_latin(left) == has_non_latin(right)


def split_featured_title(title: str) -> tuple[str, str]:
    """Return a base title and credits carried by feature annotations."""
    featured = []

    def remove(match: re.Match) -> str:
        if who := match.group("who").strip():
            featured.append(who)
        return ""

    base = BRACKETED_FEATURE.sub(remove, clean_title(title))
    base = TRAILING_FEATURE.sub(remove, base)
    return re.sub(r"\s{2,}", " ", base).strip(" -–—"), ", ".join(featured)


def credit_contains(credit: str, wanted: str) -> bool:
    wanted_tokens = set(normalize(wanted))
    return bool(wanted_tokens) and wanted_tokens <= set(normalize(credit))


def combine_credits(artist: str, featured: str) -> str:
    artist, featured = artist.strip(), featured.strip()
    if not featured or credit_contains(artist, featured):
        return artist
    return ", ".join(value for value in (artist, featured) if value)


def track_identity(artist: str, title: str) -> TrackIdentity:
    """Return lookup-only title, complete credit, and featured credit."""
    base_title, featured = split_featured_title(title)
    return TrackIdentity(base_title, combine_credits(artist, featured), featured)


def title_similarity(candidate: str, title: str) -> float:
    return similarity(track_identity("", candidate)[0], track_identity("", title)[0])


def credit_similarity(
    candidate_artist: str, candidate_title: str, artist: str, title: str
) -> float:
    candidate_credit = track_identity(candidate_artist, candidate_title)[1]
    wanted_credit = track_identity(artist, title)[1]
    return similarity(candidate_credit, wanted_credit)


def artist_agrees(candidate: str, artist: str) -> bool:
    """Require a meaningful shared token before accepting fuzzy similarity."""
    if not artist:
        return True
    shared = {
        token
        for token in set(normalize(candidate)) & set(normalize(artist))
        if len(token) > 1
    }
    return bool(shared) and similarity(candidate, artist) >= MIN_ARTIST_SIMILARITY


def candidate_agrees(
    candidate_artist: str, candidate_title: str, artist: str, title: str
) -> bool:
    """Require matching title identity and preserve explicit featured credits."""
    candidate_credit = track_identity(candidate_artist, candidate_title)[1]
    _, wanted_credit, wanted_features = track_identity(artist, title)
    return (
        title_similarity(candidate_title, title) >= MIN_TITLE_SIMILARITY
        and artist_agrees(candidate_credit, wanted_credit)
        and (not wanted_features or credit_contains(candidate_credit, wanted_features))
    )


def match_score(
    candidate_artist: str, candidate_title: str, artist: str, title: str
) -> float:
    title_score = title_similarity(candidate_title, title)
    return title_score if not artist else 0.6 * title_score + 0.4 * credit_similarity(
        candidate_artist, candidate_title, artist, title
    )


def strip_release_suffix(album: str) -> str:
    return re.sub(
        r"\s*-\s*(?:Single|EP)\s*$", "", album, flags=re.IGNORECASE
    ).strip()


def album_similarity(candidate: str, album: str) -> float:
    return similarity(strip_release_suffix(candidate), strip_release_suffix(album))


def album_agrees(candidate: str, album: str) -> bool:
    return not album or album_similarity(candidate, album) >= MIN_ALBUM_SIMILARITY


def primary_artist(album_artist: str, artist: str) -> str:
    """Return the release owner rather than a collaboration-specific credit."""
    if album_artist:
        return album_artist
    return re.split(
        r"\s*(?:,|&|;|\bfeat\.?\b|\bft\.?\b|\bwith\b)\s*", artist, maxsplit=1
    )[0].strip()


def credit_names(artist: str, title: str = "") -> list[str]:
    """Return distinct credited names while keeping names containing 'and' whole."""
    names: list[str] = []
    for raw_name in CREDIT_SEPARATOR.split(track_identity(artist, title)[1]):
        name = raw_name.strip()
        if name and not any(
            similarity(name, present) >= CREDIT_NAME_SIMILARITY for present in names
        ):
            names.append(name)
    return names


def missing_credit_names(
    current_artist: str,
    current_title: str,
    proposed_artist: str,
    proposed_title: str,
) -> list[str]:
    """Return local credits absent from the proposed artist/title pair."""
    proposed_names = credit_names(proposed_artist, proposed_title)
    return [
        name
        for name in credit_names(current_artist, current_title)
        if not any(
            similarity(name, proposed) >= CREDIT_NAME_SIMILARITY
            for proposed in proposed_names
        )
    ]


def search_variants(artist: str, title: str) -> list[tuple[str, str]]:
    """Search both common provider layouts for a featured credit."""
    cleaned = clean_title(title)
    base_title, combined_credit, _ = track_identity(artist, cleaned)
    variants = [(artist.strip(), cleaned), (combined_credit, base_title)]
    seen = set()
    unique = []
    for query_artist, query_title in variants:
        identity = query_artist.casefold(), query_title.casefold()
        if query_title and identity not in seen:
            seen.add(identity)
            unique.append((query_artist, query_title))
    return unique


def drop_redundant_feat(title: str, artist: str) -> str:
    """Remove a title feature only when the artist credit already carries it."""
    if not artist:
        return title

    def prune(match: re.Match) -> str:
        return "" if credit_contains(artist, match.group("who")) else match.group(0)

    return re.sub(
        r"\s{2,}", " ", TRAILING_FEATURE.sub(prune, BRACKETED_FEATURE.sub(prune, title))
    ).strip()


def split_leading_artist(title: str, artist: str) -> str:
    """Drop a repeated artist prefix from a YouTube-style title."""
    if " - " not in title:
        return title
    left, _, right = title.partition(" - ")
    return right.strip() if right and (not artist or similarity(left, artist) >= 0.5) else title


def bucket_index(parts: tuple[str, ...]) -> int:
    return next(
        (
            index
            for index in range(len(parts) - 1, -1, -1)
            if BUCKET_ARTISTS.search(parts[index]) or BUCKET_ALBUMS.search(parts[index])
        ),
        -1,
    )


def folder_hints(path: Path, root: Path) -> tuple[str, str]:
    """Interpret root/artist[/album]/file; [G]/[C] buckets reset that shape."""
    try:
        parts = path.relative_to(root).parts[:-1]
    except ValueError:
        return "", ""
    if not parts:
        return "", ""

    bucket = bucket_index(parts)
    if bucket >= 0:
        inner = parts[bucket + 1 :]
        if not inner:
            return "", ""
        if BUCKET_ALBUMS.search(parts[bucket]):
            return "", inner[-1]
        return inner[0], inner[-1] if len(inner) > 1 else ""
    return (parts[0], "") if len(parts) == 1 else (parts[-2], parts[-1])


def album_context(path: Path, tags, root: Path) -> tuple[str, tuple]:
    """Prefer the library directory's album, falling back to tags for loose files."""
    directory_artist, directory_album = folder_hints(path, root)
    album = directory_album or existing(tags, "album")
    if not album:
        return "", ()
    owner = (
        directory_artist
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
    """Return distinct identities, preferring filenames over video-uploader tags."""
    file_artist, file_title = parse_filename(path)
    tag_artist, tag_title = existing(tags, "artist"), existing(tags, "title")
    directory_artist, _ = folder_hints(path, root)
    candidates = []
    if file_artist and file_title:
        candidates.append((file_artist, file_title))
    if tag_title:
        candidates.append((tag_artist, split_leading_artist(tag_title, tag_artist)))
    if file_title and not file_artist:
        if directory_artist:
            candidates.append((directory_artist, file_title))
        if tag_artist or not directory_artist:
            candidates.append((tag_artist, file_title))

    seen = set()
    unique = []
    for artist, title in candidates:
        identity = candidate_key(artist, title)
        if title and identity not in seen:
            seen.add(identity)
            unique.append((artist.strip(), title.strip()))
    return unique


def first_artist_fallbacks(
    candidates: list[tuple[str, str]],
) -> list[tuple[str, str]]:
    """Build lean first-artist searches without displacing exact candidates."""
    seen = {candidate_key(artist, title) for artist, title in candidates}
    fallbacks = []
    for artist, title in candidates:
        first_artist = primary_artist("", artist)
        identity = candidate_key(first_artist, title)
        if first_artist and identity not in seen:
            seen.add(identity)
            fallbacks.append((first_artist, title))
    return fallbacks
