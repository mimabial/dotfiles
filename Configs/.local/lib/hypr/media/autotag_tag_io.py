from __future__ import annotations

import base64
from pathlib import Path
from mutagen import MutagenError
from mutagen.easyid3 import EasyID3
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3, ID3NoHeaderError
from mutagen.oggopus import OggOpus
from audio_tags import VORBIS, read_tags
from autotag_identity import MIN_TITLE_SIMILARITY, drop_redundant_feat, existing, missing_credit_names, parse_filename, title_similarity, track_identity


# The picture-type and text-encoding codes FLAC and ID3 share.
PICTURE_TYPE_FRONT_COVER = 3


ID3_ENCODING_UTF8 = 3


NON_TAG_FIELDS = {"artwork_url", "_preserved_credits"}


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
        front = next((picture for picture in pictures if picture.type == PICTURE_TYPE_FRONT_COVER), pictures[0])
        return front.data
    except (ID3NoHeaderError, MutagenError, TypeError, ValueError):
        return b""


def embed_artwork(path: Path, data: bytes) -> None:
    width, height = jpeg_size(data)
    picture = Picture()
    picture.data, picture.type, picture.mime = data, PICTURE_TYPE_FRONT_COVER, "image/jpeg"
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
        frames.add(APIC(encoding=ID3_ENCODING_UTF8, mime="image/jpeg", type=PICTURE_TYPE_FRONT_COVER, desc="Cover", data=data))
        frames.save(path)


def write_tags(path: Path, meta: dict, force: bool, tags=None) -> dict:
    if tags is None:
        tags = read_tags(path)
    is_vorbis = path.suffix.lower() in VORBIS
    valid_tag_keys = None if is_vorbis else set(EasyID3.valid_keys.keys())

    written = {}
    for field, value in meta.items():
        if not value or field in NON_TAG_FIELDS:
            continue
        if valid_tag_keys is not None and field not in valid_tag_keys:
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
    """Forced writes must not narrow the credits."""
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

