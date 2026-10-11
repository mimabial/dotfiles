from pathlib import Path

from mutagen.easyid3 import EasyID3
from mutagen.flac import FLAC
from mutagen.id3 import ID3NoHeaderError
from mutagen.mp3 import MP3
from mutagen.oggopus import OggOpus

SUPPORTED = {".mp3", ".opus", ".flac"}
SUPPORTED_LABEL = ",".join(sorted(suffix[1:] for suffix in SUPPORTED))
VORBIS = {".opus", ".flac"}


def parse_extensions(raw: str) -> set[str]:
    return {"." + value.strip().lstrip(".").casefold() for value in raw.split(",") if value.strip()}


def selected_extensions(raw: str) -> set[str]:
    wanted = parse_extensions(raw) if raw else set(SUPPORTED)
    unknown = wanted - SUPPORTED
    if unknown:
        raise ValueError(f"unsupported extension(s): {', '.join(sorted(unknown))}")
    return wanted


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
