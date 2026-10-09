#!/usr/bin/env python3
import html
import json
import math
import os
import sys
from dataclasses import dataclass


PROGRESS_BAR_CELLS = 20


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


def load_palette_colors() -> dict:
    state_home = os.path.expanduser(os.getenv("XDG_STATE_HOME", "~/.local/state"))
    try:
        with open(os.path.join(state_home, "hypr", "active-palette.json"), encoding="utf-8") as f:
            palette = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}
    named = {"background": palette.get("bg"), "foreground": palette.get("fg"), "cursor": palette.get("cursor")}
    named.update((f"color{index}", color) for index, color in enumerate(palette.get("colors", [])))
    return {name: color for name, color in named.items() if color}


def normalize_color(value: str, palette_colors: dict, fallback: str) -> str:
    if not value:
        return fallback
    value = value.strip()
    if not value:
        return fallback
    lookup = palette_colors.get(value) or palette_colors.get(value.lower())
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


DEFAULT_MAX_LENGTH = 70
MAX_LENGTH_BOUNDS = (10, 200)
MAX_PREFIX_LENGTH = 20
MAX_STANDBY_TEXT_LENGTH = 50
MAX_SEPARATOR_LENGTH = 10
FALLBACK_COLOR = "#FFFFFF"
FALLBACK_EMPTY_COLOR = "#666666"
HEX_COLOR_LENGTHS = {len("#RGB"), len("#RRGGBB"), len("#RRGGBBAA")}


def configured_max_length() -> int:
    try:
        max_length = int(os.getenv("MEDIAPLAYER_MAX_LENGTH", str(DEFAULT_MAX_LENGTH)))
        return max(MAX_LENGTH_BOUNDS[0], min(MAX_LENGTH_BOUNDS[1], max_length))
    except (ValueError, TypeError):
        print(
            f"WARNING: Invalid MEDIAPLAYER_MAX_LENGTH, using default {DEFAULT_MAX_LENGTH}", file=sys.stderr
        )
        return DEFAULT_MAX_LENGTH


def tooltip_colors() -> dict[str, str]:
    palette_colors = load_palette_colors()
    artist_default = palette_colors.get("color4", FALLBACK_COLOR)
    defaults = {
        "artist": artist_default,
        "track": palette_colors.get("foreground", FALLBACK_COLOR),
        "progress": palette_colors.get("color2", artist_default),
        "empty": palette_colors.get("color8", palette_colors.get("color0", FALLBACK_EMPTY_COLOR)),
        "time": palette_colors.get("foreground", FALLBACK_COLOR),
    }

    colors = {}
    for role, default in defaults.items():
        name = f"{role}_color"
        color = normalize_color(os.getenv(f"MEDIAPLAYER_TOOLTIP_{role.upper()}_COLOR", ""), palette_colors, default)
        if not color.startswith("#") or len(color) not in HEX_COLOR_LENGTHS:
            print(f"WARNING: Invalid color format for {name}: {color}", file=sys.stderr)
            color = FALLBACK_COLOR
        colors[name] = color
    return colors


def validate_ui_config() -> MediaPlayerUiConfig:
    return MediaPlayerUiConfig(
        max_length_module=configured_max_length(),
        prefix_playing=str(os.getenv("MEDIAPLAYER_PREFIX_PLAYING", ""))[:MAX_PREFIX_LENGTH],
        prefix_paused=str(os.getenv("MEDIAPLAYER_PREFIX_PAUSED", ""))[:MAX_PREFIX_LENGTH],
        standby_text=str(os.getenv("MEDIAPLAYER_STANDBY_TEXT", " MPlayer"))[:MAX_STANDBY_TEXT_LENGTH],
        artist_track_separator=str(os.getenv("MEDIAPLAYER_ARTIST_TRACK_SEPARATOR", "  "))[:MAX_SEPARATOR_LENGTH],
        **tooltip_colors(),
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


def format_time_multiple_lines(
    seconds: float, playing: bool, *, countdown: bool = False
) -> str:
    try:
        total = quantize_display_seconds(seconds, countdown=countdown)
        h, m = divmod(total, 3600)
        m, s = divmod(m, 60)
        icon = "󰼛" if playing else "󰈅"
        if h:
            return f"{icon}{h:02d}\n:{m:02d}\n:{s:02d}"
        return f"{icon}{m:02d}\n:{s:02d}"
    except Exception:
        return " \n:00"


# All three from Material Design so the states share an optical box.
STATE_ICONS = {
    "Playing": "",
    "Paused": "",
    "Stopped": "",
}


def format_state_icon(status: str) -> str:
    return STATE_ICONS.get(status, STATE_ICONS["Stopped"])


def format_live_multiple_lines(playing: bool) -> str:
    icon = "󰼛" if playing else " "
    return f"{icon}LI\n:VE"


def format_time_single_line(
    seconds: float, playing: bool, *, countdown: bool = False
) -> str:
    icon = "󰼛 " if playing else " "
    return f"{icon}{format_time(seconds, countdown=countdown)}"


def format_live_single_line(playing: bool) -> str:
    icon = "󰼛 " if playing else " "
    return f"{icon}LIVE"


def create_tooltip_text(
    artist,
    track,
    current_position_seconds,
    duration_seconds,
    player_name,
    ui_config: MediaPlayerUiConfig,
    *,
    is_live_stream=False,
    loop_status=None,
    shuffle_status=None,
) -> str:
    tooltip = ""
    if artist or track:
        tooltip += (
            f'<span foreground="{ui_config.track_color}"><b>{escape_markup_text(track)}</b></span>'
        )
        tooltip += (
            f'\n<span foreground="{ui_config.artist_color}">'
            f"<i>{escape_markup_text(artist)}</i></span>\n"
        )
        if is_live_stream:
            tooltip += (
                f'<span foreground="{ui_config.progress_color}"><b>LIVE</b></span>'
                f' <span foreground="{ui_config.time_color}">{format_time(current_position_seconds)}</span>'
            )
        elif duration_seconds > 0:
            progress = max(
                0, min(PROGRESS_BAR_CELLS, int((current_position_seconds / duration_seconds) * PROGRESS_BAR_CELLS))
            )
            bar = (
                f'<span foreground="{ui_config.progress_color}">{"─" * progress}</span>'
                f'<span foreground="{ui_config.empty_color}">{"─" * (PROGRESS_BAR_CELLS - progress)}</span>'
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
                loop_label = loop_glyphs.get(loop_status, str(loop_status))
                tooltip += (
                    f"\n<span foreground='{ui_config.track_color}'>"
                    f"{escape_markup_text(loop_label)}</span>"
                )
            if shuffle_status is not None:
                shuffle_glyph = "󰒟 Shuffle On" if shuffle_status else "󰒞 Shuffle Off"
                tooltip += f"\n<span foreground='{ui_config.track_color}'>{shuffle_glyph}</span>"
        tooltip += f"\n<span>{escape_markup_text(player_name)}</span>"
    tooltip += (
        f"\n<span size='x-small' foreground='{ui_config.track_color}'>"
        f"\n󰐎 click to play/pause\n scroll to switch player\n󱥣 rightclick for options</span>"
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
    prefix = escape_markup_text(ui_config.prefix_playing if playing else ui_config.prefix_paused)
    prefix_separator = "  "
    full_length = len(artist + track)

    if track and not artist:
        if len(track) > ui_config.max_length_module:
            track = track[: ui_config.max_length_module].rstrip() + "…"
        return f"{prefix}{prefix_separator}<b>{escape_markup_text(track)}</b>"

    if track and artist:
        artist = artist.split(",")[0].split("&")[0].strip()
        if full_length > ui_config.max_length_module:
            artist_weight = 0.65
            artist_limit = min(
                int(ui_config.max_length_module * artist_weight), len(artist)
            )
            artist_spare_weight = max(
                0, artist_weight - (artist_limit / ui_config.max_length_module)
            )
            track_weight = 1 - artist_weight + artist_spare_weight
            track_limit = min(
                int(ui_config.max_length_module * track_weight), len(track)
            )
            track_spare_weight = max(0, track_weight - (track_limit / ui_config.max_length_module))

            if artist_spare_weight == 0 and track_spare_weight > 0:
                artist_limit = artist_limit + int(ui_config.max_length_module * track_spare_weight)
            elif artist_spare_weight > 0 and track_spare_weight == 0:
                track_limit = track_limit + int(ui_config.max_length_module * artist_spare_weight)

            if len(artist) > artist_limit:
                artist = artist[:artist_limit].rstrip() + "…"
            if len(track) > track_limit:
                track = track[:track_limit].rstrip() + "…"

        return (
            f"{prefix}{prefix_separator}<i>{escape_markup_text(artist)}</i>"
            f"{escape_markup_text(ui_config.artist_track_separator)}<b>{escape_markup_text(track)}</b>"
        )

    standby_text = escape_markup_text(ui_config.standby_text)
    if standby_player_name:
        return f"<b>{standby_text} {escape_markup_text(standby_player_name)}</b>"
    return f"<b>{standby_text}</b>"


def escape_markup_text(string):
    return html.escape(str(string), quote=False)
