from __future__ import annotations

from typing import TypedDict


class TrackTags(TypedDict, total=False):
    """Every key a provider may return. No provider returns all of them:
    artwork_url is iTunes-only, musicbrainz_* come from AcoustID/MusicBrainz,
    and _preserved_credits is added later by prepare_metadata."""

    title: str
    artist: str
    albumartist: str
    album: str
    date: str
    tracknumber: str
    genre: str
    artwork_url: str
    musicbrainz_trackid: str
    musicbrainz_releasegroupid: str
    _preserved_credits: str


class Unidentified(Exception):
    pass

