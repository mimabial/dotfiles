#!/usr/bin/env python3
from dataclasses import dataclass, field, replace

from mediaplayer_browser import (
    get_ytdlp_media_info,
    is_youtube_url,
    youtube_position_is_untrusted,
)


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

    def same_track_as(self, previous: "MediaMetadata") -> bool:
        if self.media_url and previous.media_url:
            return self.media_url == previous.media_url
        if self.track and previous.track:
            same_track = self.track == previous.track
            if self.artist and previous.artist:
                same_track = same_track and self.artist == previous.artist
            return same_track
        if self.track_id and previous.track_id:
            return self.track_id == previous.track_id
        return False


@dataclass
class PlaybackState:
    metadata: MediaMetadata = field(default_factory=MediaMetadata)
    track_key: str = ""
    position_seconds: float = 0.0
    seek_at: float = 0.0
    seek_position: float | None = None
    raw_track: str = ""
    title_media_url: str = ""

    def reset(self) -> None:
        self.metadata = MediaMetadata()
        self.track_key = ""
        self.position_seconds = 0.0
        self.seek_at = 0.0
        self.seek_position = None
        self.raw_track = ""
        self.title_media_url = ""

    def record_seek(self, position_seconds: float | None, observed_at: float) -> None:
        self.seek_at = observed_at
        self.seek_position = position_seconds


@dataclass(frozen=True)
class PlaybackSnapshot:
    player_name: str
    status: str
    reported_position_seconds: float
    metadata: MediaMetadata
    observed_at: float
    loop_status: str | None = None
    shuffle_status: bool | None = None


@dataclass(frozen=True)
class ResolvedPlayback:
    player_name: str
    status: str
    metadata: MediaMetadata
    position_seconds: float
    position_untrusted: bool
    loop_status: str | None = None
    shuffle_status: bool | None = None

    @property
    def is_playing(self) -> bool:
        return self.status == "Playing"

    @property
    def countdown_display(self) -> bool:
        return bool(
            self.metadata.duration_seconds
            and not self.metadata.is_live_stream
            and not self.position_untrusted
        )

    @property
    def time_display_seconds(self) -> float:
        if self.countdown_display:
            return max(
                0.0,
                round(self.metadata.duration_seconds - self.position_seconds, 2),
            )
        return self.position_seconds


def build_track_identity_key(
    player_name: str,
    track_id: str,
    media_url: str,
    track: str,
    artist: str,
) -> str:
    return f"{player_name}|{track_id}|{media_url}|{track}|{artist}"


def read_player_metadata(player) -> MediaMetadata:
    snapshot = MediaMetadata()
    try:
        metadata = player.props.metadata
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


def resolve_metadata_duration(
    snapshot: MediaMetadata,
    last_metadata: MediaMetadata,
) -> MediaMetadata:
    same_track_as_last = snapshot.same_track_as(last_metadata)
    last_duration_seconds = max(0.0, last_metadata.duration_seconds)
    ytdlp_info = get_ytdlp_media_info(
        snapshot.media_url,
        same_track_as_last=same_track_as_last,
        last_duration_seconds=last_duration_seconds,
        last_live_status=last_metadata.ytdlp_live_status,
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
    seek_position: float | None,
    seek_age: float,
    last_metadata: MediaMetadata,
    title_is_stale: bool = False,
) -> tuple[MediaMetadata, MediaMetadata]:
    resolved = replace(raw_metadata)
    recent_seek_to_start = (
        seek_position is not None
        and 0.0 <= seek_age <= 2.5
        and seek_position <= 3.0
    )
    same_track_as_last = raw_metadata.same_track_as(last_metadata)
    youtube_url_changed = (
        raw_metadata.is_youtube
        and bool(last_metadata.media_url)
        and raw_metadata.media_url != last_metadata.media_url
    )

    if title_is_stale:
        resolved.track = ""
        resolved.artist = ""
    elif not recent_seek_to_start:
        if not resolved.track and last_metadata.track:
            resolved.track = last_metadata.track
        if not resolved.artist and last_metadata.artist:
            resolved.artist = last_metadata.artist

    allow_duration_fallback = not (recent_seek_to_start and not same_track_as_last)
    if (
        allow_duration_fallback
        and resolved.duration_seconds <= 0
        and last_metadata.duration_seconds > 0
        and (not raw_metadata.identity_present or same_track_as_last)
    ):
        resolved.duration_seconds = last_metadata.duration_seconds

    if youtube_url_changed and not (
        raw_metadata.ytdlp_duration_seconds
        and raw_metadata.ytdlp_duration_seconds > 0
    ):
        resolved.duration_seconds = 0.0

    updated_metadata = last_metadata
    if resolved.track or resolved.artist or resolved.duration_seconds > 0:
        track_id = raw_metadata.track_id
        if not track_id and same_track_as_last:
            track_id = last_metadata.track_id
        live_status = raw_metadata.ytdlp_live_status
        if not live_status and same_track_as_last:
            live_status = last_metadata.ytdlp_live_status
        updated_metadata = MediaMetadata(
            track=resolved.track,
            artist=resolved.artist,
            track_id=track_id,
            media_url=raw_metadata.media_url,
            duration_seconds=max(0.0, resolved.duration_seconds),
            ytdlp_live_status=live_status,
        )

    return resolved, updated_metadata


def resolve_playback(
    snapshot: PlaybackSnapshot,
    state: PlaybackState,
) -> ResolvedPlayback:
    seek_age = snapshot.observed_at - state.seek_at
    position_seconds = snapshot.reported_position_seconds
    if (
        state.seek_position is not None
        and 0.0 <= seek_age <= 2.0
        and abs(state.seek_position - position_seconds) > 1.0
    ):
        position_seconds = state.seek_position

    raw_metadata = resolve_metadata_duration(snapshot.metadata, state.metadata)
    if raw_metadata.track != state.raw_track:
        state.raw_track = raw_metadata.track
        state.title_media_url = raw_metadata.media_url
    title_is_stale = bool(
        raw_metadata.is_youtube
        and state.title_media_url
        and raw_metadata.media_url != state.title_media_url
    )
    metadata, state.metadata = resolve_browser_metadata_fallbacks(
        raw_metadata,
        seek_position=state.seek_position,
        seek_age=seek_age,
        last_metadata=state.metadata,
        title_is_stale=title_is_stale,
    )
    duration_seconds = max(0.0, round(metadata.duration_seconds, 2))
    metadata.duration_seconds = duration_seconds

    track_key = build_track_identity_key(
        snapshot.player_name,
        metadata.track_id,
        metadata.media_url,
        metadata.track,
        metadata.artist,
    )
    recent_seek_to_end = (
        state.seek_position is not None
        and 0.0 <= seek_age <= 2.5
        and duration_seconds > 0
        and state.seek_position >= max(0.0, duration_seconds - 5.0)
    )
    position_seconds = max(0.0, position_seconds)
    position_untrusted = youtube_position_is_untrusted(
        resolved_metadata=metadata,
        raw_metadata=raw_metadata,
        reported_position_seconds=position_seconds,
        duration_seconds=duration_seconds,
        is_playing=snapshot.status == "Playing",
        recent_seek_to_end=recent_seek_to_end,
        previous_track_key=state.track_key,
        current_track_key=track_key,
        previous_raw_position=state.position_seconds,
    )
    if position_untrusted:
        position_seconds = (
            state.position_seconds if state.track_key == track_key else 0.0
        )
    position_seconds = max(0.0, round(position_seconds, 2))
    if duration_seconds > 0:
        position_seconds = min(position_seconds, duration_seconds)

    state.track_key = track_key
    state.position_seconds = position_seconds
    return ResolvedPlayback(
        player_name=snapshot.player_name,
        status=snapshot.status,
        metadata=metadata,
        position_seconds=position_seconds,
        position_untrusted=position_untrusted,
        loop_status=snapshot.loop_status,
        shuffle_status=snapshot.shuffle_status,
    )
