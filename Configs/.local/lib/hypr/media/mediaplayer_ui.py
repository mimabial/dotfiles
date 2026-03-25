#!/usr/bin/env python3
import json
import math
import os
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class MediaPlayerUiConfig:
    max_length_module: int
    prefix_playing: str
    prefix_paused: str
    standby_text: str
    artist_track_separator: str
    artist_color: str
    track_color: str
    progress_color: str
    empty_color: str
    time_color: str


def load_pywal_colors(cache_root: str) -> dict:
    colors = {}
    colors_json = os.path.join(cache_root, "wal", "colors.json")
    try:
        with open(colors_json, encoding="utf-8") as f:
            data = json.load(f)
        colors.update(data.get("special", {}))
        colors.update(data.get("colors", {}))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return {}
    return colors


def normalize_color(value: str, wal_colors: dict, fallback: str) -> str:
    if not value:
        return fallback
    value = value.strip()
    if not value:
        return fallback
    lookup = wal_colors.get(value) or wal_colors.get(value.lower())
    if lookup:
        return lookup
    if value.startswith("#"):
        return value
    if len(value) in (3, 6, 8):
        return f"#{value}"
    return fallback


def emit_json_output(output: dict) -> None:
    try:
        sys.stdout.write(json.dumps(output, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, OSError):
        os._exit(0)


def validate_ui_config() -> MediaPlayerUiConfig:
    try:
        max_length_module = int(os.getenv("MEDIAPLAYER_MAX_LENGTH", "70"))
        max_length_module = max(10, min(200, max_length_module))
    except (ValueError, TypeError):
        print("WARNING: Invalid MEDIAPLAYER_MAX_LENGTH, using default 70", file=sys.stderr)
        max_length_module = 70

    prefix_playing = str(os.getenv("MEDIAPLAYER_PREFIX_PLAYING", ""))[:20]
    prefix_paused = str(os.getenv("MEDIAPLAYER_PREFIX_PAUSED", ""))[:20]
    standby_text = str(os.getenv("MEDIAPLAYER_STANDBY_TEXT", " MPlayer"))[:50]
    artist_track_separator = str(os.getenv("MEDIAPLAYER_ARTIST_TRACK_SEPARATOR", "  "))[:10]

    xdg_cache = os.path.expanduser(os.getenv("XDG_CACHE_HOME", "~/.cache"))
    wal_colors = load_pywal_colors(xdg_cache)
    default_artist = wal_colors.get("color4", "#FFFFFF")
    default_track = wal_colors.get("foreground", "#FFFFFF")
    default_progress = wal_colors.get("color2", default_artist)
    default_empty = wal_colors.get("color8", wal_colors.get("color0", "#666666"))
    default_time = wal_colors.get("foreground", "#FFFFFF")

    color_values = {
        "artist_color": normalize_color(os.getenv("MEDIAPLAYER_TOOLTIP_ARTIST_COLOR", ""), wal_colors, default_artist),
        "track_color": normalize_color(os.getenv("MEDIAPLAYER_TOOLTIP_TRACK_COLOR", ""), wal_colors, default_track),
        "progress_color": normalize_color(os.getenv("MEDIAPLAYER_TOOLTIP_PROGRESS_COLOR", ""), wal_colors, default_progress),
        "empty_color": normalize_color(os.getenv("MEDIAPLAYER_TOOLTIP_EMPTY_COLOR", ""), wal_colors, default_empty),
        "time_color": normalize_color(os.getenv("MEDIAPLAYER_TOOLTIP_TIME_COLOR", ""), wal_colors, default_time),
    }

    for var_name, color_value in color_values.items():
        if not color_value.startswith("#") or len(color_value) not in [4, 7, 9]:
            print(f"WARNING: Invalid color format for {var_name}: {color_value}", file=sys.stderr)
            color_values[var_name] = "#FFFFFF"

    return MediaPlayerUiConfig(
        max_length_module=max_length_module,
        prefix_playing=prefix_playing,
        prefix_paused=prefix_paused,
        standby_text=standby_text,
        artist_track_separator=artist_track_separator,
        artist_color=color_values["artist_color"],
        track_color=color_values["track_color"],
        progress_color=color_values["progress_color"],
        empty_color=color_values["empty_color"],
        time_color=color_values["time_color"],
    )


def quantize_display_seconds(seconds: float, *, countdown: bool = False) -> int:
    seconds = max(0.0, float(seconds))
    if countdown:
        return max(0, int(math.ceil(seconds - 1e-9)))
    return max(0, int(math.floor(seconds + 1e-9)))


def format_time(seconds: float, *, countdown: bool = False) -> str:
    try:
        total = quantize_display_seconds(seconds, countdown=countdown)
        h, m = divmod(total, 3600)
        m, s = divmod(m, 60)
        return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"
    except Exception:
        return "00:00"


def format_time_multiple_lines(seconds: float, playing: bool, *, countdown: bool = False) -> str:
    try:
        total = quantize_display_seconds(seconds, countdown=countdown)
        h, m = divmod(total, 3600)
        m, s = divmod(m, 60)
        icon = "󰼛" if playing else " "
        if h:
            return f"{icon}{h:02d}\n:{m:02d}\n:{s:02d}"
        return f"{icon}{m:02d}\n:{s:02d}"
    except Exception:
        return " \n:00"


def format_live_multiple_lines(playing: bool) -> str:
    icon = "󰼛" if playing else " "
    return f"{icon}LI\n:VE"


def create_tooltip_text(
    artist,
    track,
    current_position_seconds,
    duration_seconds,
    p_name,
    ui_config: MediaPlayerUiConfig,
    *,
    is_live_stream=False,
    loop_status=None,
    shuffle_status=None,
) -> str:
    tooltip = ""
    if artist or track:
        tooltip += f'<span foreground="{ui_config.track_color}"><b>{track}</b></span>'
        tooltip += f'\n<span foreground="{ui_config.artist_color}"><i>{artist}</i></span>\n'
        if is_live_stream:
            tooltip += (
                f'<span foreground="{ui_config.progress_color}"><b>LIVE</b></span>'
                f' <span foreground="{ui_config.time_color}">{format_time(current_position_seconds)}</span>'
            )
        elif duration_seconds > 0:
            progress = int((current_position_seconds / duration_seconds) * 20)
            bar = (
                f'<span foreground="{ui_config.progress_color}">{"█" * progress}</span>'
                f'<span foreground="{ui_config.empty_color}">{"─" * (20 - progress)}</span>'
            )
            tooltip += (
                f'<span foreground="{ui_config.time_color}">{format_time(current_position_seconds)}</span> '
                f"{bar} "
                f'<span foreground="{ui_config.time_color}">{format_time(duration_seconds)}</span>'
            )
            if loop_status is not None:
                loop_glyphs = {
                    "None": "󰑗 No Loop",
                    "Track": "󰑖 Loop Once",
                    "Playlist": "󰑘 Loop Playlist",
                }
                tooltip += f"\n<span foreground='{ui_config.track_color}'>{loop_glyphs.get(loop_status, str(loop_status))}</span>"
            if shuffle_status is not None:
                shuffle_glyph = "󰒟 Shuffle On" if shuffle_status else "󰒞 Shuffle Off"
                tooltip += f"\n<span foreground='{ui_config.track_color}'>{shuffle_glyph}</span>"
        tooltip += f"\n<span>{p_name}</span>"
    tooltip += (
        f"\n<span size='x-small' foreground='{ui_config.track_color}'>"
        f"\n󰐎 click to play/pause\n scroll to seek\n󱥣 rightclick for options</span>"
    )
    return tooltip


def format_artist_track(
    artist,
    track,
    playing,
    ui_config: MediaPlayerUiConfig,
    *,
    standby_player_name: str = "",
):
    prefix = ui_config.prefix_playing if playing else ui_config.prefix_paused
    prefix_separator = "  "
    full_length = len(artist + track)

    if track and not artist:
        if len(track) > ui_config.max_length_module:
            track = track[: ui_config.max_length_module].rstrip() + "…"
        return f"{prefix}{prefix_separator}<b>{track}</b>"

    if track and artist:
        artist = artist.split(",")[0].split("&")[0].strip()
        if full_length > ui_config.max_length_module:
            artist_weight = 0.65
            artist_limit = min(int(ui_config.max_length_module * artist_weight), len(artist))
            a_gain = max(0, artist_weight - (artist_limit / ui_config.max_length_module))
            track_weight = 1 - artist_weight + a_gain
            track_limit = min(int(ui_config.max_length_module * track_weight), len(track))
            t_gain = max(0, track_weight - (track_limit / ui_config.max_length_module))

            if a_gain == 0 and t_gain > 0:
                artist_limit = artist_limit + int(ui_config.max_length_module * t_gain)
            elif a_gain > 0 and t_gain == 0:
                track_limit = track_limit + int(ui_config.max_length_module * a_gain)

            if len(artist) > artist_limit:
                artist = artist[:artist_limit].rstrip() + "…"
            if len(track) > track_limit:
                track = track[:track_limit].rstrip() + "…"

        return (
            f"{prefix}{prefix_separator}<i>{artist}</i>"
            f"{ui_config.artist_track_separator}<b>{track}</b>"
        )

    if standby_player_name:
        return f"<b>{ui_config.standby_text} {standby_player_name}</b>"
    return f"<b>{ui_config.standby_text}</b>"


def escape(string):
    return string.replace("&", "&amp;")
