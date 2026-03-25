#!/usr/bin/env python3
from dataclasses import dataclass, replace

from mediaplayer_browser import get_ytdlp_media_info, is_youtube_url


@dataclass
class MediaMetadata:
    track: str = ""
    artist: str = ""
    track_id: str = ""
    media_url: str = ""
    duration_seconds: float = 0.0
    ytdlp_duration_seconds: float | None = None
    ytdlp_live_status: str = ""

    @property
    def identity_present(self) -> bool:
        return bool(self.media_url or self.track_id or self.track or self.artist)

    @property
    def is_youtube(self) -> bool:
        return is_youtube_url(self.media_url)

    @property
    def is_live_stream(self) -> bool:
        return self.ytdlp_live_status == "is_live"

    def same_track_as(self, previous: dict) -> bool:
        if self.media_url and previous["media_url"]:
            return self.media_url == previous["media_url"]
        if self.track and previous["track"]:
            same_track = self.track == previous["track"]
            if self.artist and previous["artist"]:
                same_track = same_track and self.artist == previous["artist"]
            return same_track
        if self.track_id and previous["track_id"]:
            return self.track_id == previous["track_id"]
        return False


def build_track_identity_key(
    player_name: str,
    track_id: str,
    media_url: str,
    track: str,
    artist: str,
) -> str:
    return f"{player_name}|{track_id}|{media_url}|{track}|{artist}"


def read_player_metadata(current_player) -> MediaMetadata:
    snapshot = MediaMetadata()
    try:
        metadata = current_player.props.metadata
        if metadata:
            data = metadata.unpack()
            snapshot.track = data.get("xesam:title", "") or ""
            snapshot.artist = (
                data.get("xesam:artist", [""])[0] if "xesam:artist" in data else ""
            )
            snapshot.track_id = str(data.get("mpris:trackid", "") or "")
            snapshot.media_url = str(data.get("xesam:url", "") or "")
            snapshot.duration_seconds = data.get("mpris:length", 0) / 1e6
    except Exception:
        pass
    return snapshot


def resolve_metadata_duration(snapshot: MediaMetadata, last_metadata: dict) -> MediaMetadata:
    same_track_as_last = snapshot.same_track_as(last_metadata)
    last_duration_seconds = max(0.0, float(last_metadata.get("duration", 0.0)))
    last_live_status = str(last_metadata.get("live_status", ""))
    ytdlp_info = get_ytdlp_media_info(
        snapshot.media_url,
        same_track_as_last=same_track_as_last,
        last_duration_seconds=last_duration_seconds,
        last_live_status=last_live_status,
    )
    ytdlp_duration = ytdlp_info.duration_seconds
    resolved_duration = snapshot.duration_seconds

    if snapshot.is_youtube:
        if ytdlp_info.is_live:
            resolved_duration = 0.0
        elif ytdlp_duration and ytdlp_duration > 0:
            resolved_duration = ytdlp_duration
        elif resolved_duration >= 4 * 3600:
            resolved_duration = 0.0
    elif ytdlp_duration and ytdlp_duration > 0 and resolved_duration <= 0:
        resolved_duration = ytdlp_duration

    return replace(
        snapshot,
        duration_seconds=resolved_duration,
        ytdlp_duration_seconds=ytdlp_duration,
        ytdlp_live_status=ytdlp_info.live_status,
    )


def resolve_browser_metadata_fallbacks(
    raw_metadata: MediaMetadata,
    *,
    player_status: str,
    position_seconds: float,
    seek_position,
    seek_age: float,
    last_metadata: dict,
    position_state: dict,
) -> tuple[MediaMetadata, dict]:
    resolved = replace(raw_metadata)
    is_playing = player_status == "Playing"
    previous_raw_position = float(position_state.get("raw_position", 0.0))

    recent_seek_to_start = (
        seek_position is not None
        and 0.0 <= seek_age <= 2.5
        and float(seek_position) <= 3.0
    )
    likely_track_rollover = (
        not raw_metadata.track
        and not raw_metadata.artist
        and not raw_metadata.track_id
        and is_playing
        and previous_raw_position > 5.0
        and position_seconds <= 3.0
    )

    same_track_as_last = raw_metadata.same_track_as(last_metadata)
    youtube_url_changed = (
        raw_metadata.is_youtube
        and bool(last_metadata["media_url"])
        and raw_metadata.media_url != last_metadata["media_url"]
    )

    allow_text_fallback = not (recent_seek_to_start or likely_track_rollover)
    allow_duration_fallback = not likely_track_rollover
    if recent_seek_to_start and not same_track_as_last:
        allow_duration_fallback = False

    if allow_text_fallback and not resolved.track and last_metadata["track"]:
        resolved.track = last_metadata["track"]
    if allow_text_fallback and not resolved.artist and last_metadata["artist"]:
        resolved.artist = last_metadata["artist"]

    if (
        allow_duration_fallback
        and resolved.duration_seconds <= 0
        and last_metadata["duration"] > 0
        and (not raw_metadata.identity_present or same_track_as_last)
    ):
        resolved.duration_seconds = last_metadata["duration"]

    if youtube_url_changed and not (
        raw_metadata.ytdlp_duration_seconds and raw_metadata.ytdlp_duration_seconds > 0
    ):
        resolved.duration_seconds = 0.0

    updated_last_metadata = last_metadata
    if resolved.track or resolved.artist or resolved.duration_seconds > 0:
        cached_track_id = raw_metadata.track_id
        if not cached_track_id and same_track_as_last:
            cached_track_id = last_metadata["track_id"]
        cached_live_status = raw_metadata.ytdlp_live_status
        if not cached_live_status and same_track_as_last:
            cached_live_status = str(last_metadata.get("live_status", ""))
        updated_last_metadata = {
            "track": resolved.track,
            "artist": resolved.artist,
            "track_id": cached_track_id,
            "media_url": raw_metadata.media_url,
            "duration": resolved.duration_seconds if resolved.duration_seconds > 0 else 0.0,
            "live_status": cached_live_status,
        }

    return resolved, updated_last_metadata
