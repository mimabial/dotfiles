"""Supported audio formats and tag readers."""

from pathlib import Path

from mutagen.easyid3 import EasyID3
from mutagen.flac import FLAC
from mutagen.id3 import ID3NoHeaderError
from mutagen.mp3 import MP3
from mutagen.oggopus import OggOpus

SUPPORTED = {".mp3", ".opus", ".flac"}
VORBIS = {".opus", ".flac"}


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
