#!/usr/bin/env python3
import os
import sys

import gi

gi.require_version("Playerctl", "2.0")
import argparse
import json
import logging
import shutil
import signal
import subprocess
import threading
import time

from gi.repository import GLib, Playerctl

players_data = {}
current_player = None
_timer_id = None  # Track the timer source ID
_runtime_state_file = None
_recover_max_age_seconds = 20.0
_ytdlp_duration_cache = {}
_ytdlp_duration_lock = threading.Lock()
_ytdlp_inflight = set()
_ytdlp_timeout_seconds = 20.0


def load_env_file(filepath: str) -> None:
    try:
        with open(filepath, encoding="utf-8") as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    if line.startswith("export "):
                        line = line[len("export ") :]
                    key, value = line.strip().split("=", 1)
                    os.environ[key] = value.strip('"')
    except (FileNotFoundError, OSError) as e:
        print(f"ERROR: Error loading environment file {filepath}: {e}", file=sys.stderr)


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
    """Write one JSON line to stdout, exiting immediately if the pipe is gone."""
    try:
        sys.stdout.write(json.dumps(output, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, OSError):
        os._exit(0)


def load_runtime_position_state() -> dict:
    if not _runtime_state_file or not os.path.exists(_runtime_state_file):
        return {"track_key": "", "position": 0.0, "duration": 0.0, "wall_time": 0.0}

    try:
        with open(_runtime_state_file, "r", encoding="utf-8") as file:
            data = json.load(file)
        if isinstance(data, dict):
            return {
                "track_key": str(data.get("track_key", "")),
                "position": float(data.get("position", 0.0)),
                "duration": float(data.get("duration", 0.0)),
                "wall_time": float(data.get("wall_time", 0.0)),
            }
    except (FileNotFoundError, OSError, ValueError, json.JSONDecodeError):
        pass

    return {"track_key": "", "position": 0.0, "duration": 0.0, "wall_time": 0.0}


def save_runtime_position_state(track_key: str, position: float, duration: float) -> None:
    if not _runtime_state_file:
        return

    directory = os.path.dirname(_runtime_state_file)
    tmp_file = f"{_runtime_state_file}.tmp"
    try:
        os.makedirs(directory, exist_ok=True)
        payload = {
            "track_key": track_key,
            "position": float(position),
            "duration": float(duration),
            "wall_time": float(time.time()),
        }
        with open(tmp_file, "w", encoding="utf-8") as file:
            json.dump(payload, file)
        os.replace(tmp_file, _runtime_state_file)
    except OSError:
        pass
    finally:
        try:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)
        except OSError:
            pass


def get_recover_max_age_seconds() -> float:
    raw = os.getenv("MEDIAPLAYER_RECOVER_MAX_AGE", "").strip()
    if raw:
        try:
            value = float(raw)
            if value >= 0:
                return value
        except ValueError:
            pass
    return 20.0


def get_ytdlp_timeout_seconds() -> float:
    raw = os.getenv("MEDIAPLAYER_YTDLP_TIMEOUT", "").strip()
    if raw:
        try:
            value = float(raw)
            if value > 0:
                return value
        except ValueError:
            pass
    return 20.0


def is_youtube_url(url: str) -> bool:
    if not url:
        return False
    return (
        "youtube.com/watch" in url
        or "youtube.com/shorts/" in url
        or "music.youtube.com/watch" in url
        or "youtu.be/" in url
    )


def _parse_ytdlp_duration(stdout: str) -> float | None:
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            parsed = float(line)
            if parsed > 0:
                return parsed
        except ValueError:
            continue
    return None


def _fetch_ytdlp_duration(url: str) -> None:
    duration_value = None
    now = time.time()
    ytdlp_bin = shutil.which("yt-dlp")

    if ytdlp_bin:
        try:
            result = subprocess.run(
                [
                    ytdlp_bin,
                    "--ignore-config",
                    "--no-warnings",
                    "--skip-download",
                    "--no-playlist",
                    "--print",
                    "duration",
                    url,
                ],
                capture_output=True,
                text=True,
                timeout=_ytdlp_timeout_seconds,
            )
            if result.returncode == 0:
                duration_value = _parse_ytdlp_duration(result.stdout)
        except Exception:
            duration_value = None

    with _ytdlp_duration_lock:
        _ytdlp_duration_cache[url] = (duration_value, now)
        _ytdlp_inflight.discard(url)


def _ensure_ytdlp_fetch(url: str) -> None:
    with _ytdlp_duration_lock:
        if url in _ytdlp_inflight:
            return
        _ytdlp_inflight.add(url)

    thread = threading.Thread(target=_fetch_ytdlp_duration, args=(url,), daemon=True)
    thread.start()


def get_ytdlp_duration_seconds(url: str) -> float | None:
    if not is_youtube_url(url):
        return None

    now = time.time()
    stale_duration = None
    with _ytdlp_duration_lock:
        cached = _ytdlp_duration_cache.get(url)
        if cached is not None:
            cached_duration, cached_at = cached
            cache_ttl = 900 if cached_duration is not None else 60
            if now - cached_at < cache_ttl:
                return cached_duration
            if cached_duration is not None and cached_duration > 0:
                stale_duration = cached_duration

    # Refresh in background so UI updates are never blocked by network/subprocess lag.
    _ensure_ytdlp_fetch(url)
    return stale_duration


def validate_config() -> None:
    """Validate and sanitize configuration values"""
    global \
        max_length_module, \
        prefix_playing, \
        prefix_paused, \
        standby_text, \
        artist_track_separator

    # Validate max_length_module
    try:
        max_length_module = int(os.getenv("MEDIAPLAYER_MAX_LENGTH", "70"))
        max_length_module = max(10, min(200, max_length_module))  # Clamp between 10-200
    except (ValueError, TypeError):
        print("WARNING: Invalid MEDIAPLAYER_MAX_LENGTH, using default 70", file=sys.stderr)
        max_length_module = 70

    # Validate text configurations
    prefix_playing = str(os.getenv("MEDIAPLAYER_PREFIX_PLAYING", ""))[
        :20
    ]  # Limit length
    prefix_paused = str(os.getenv("MEDIAPLAYER_PREFIX_PAUSED", ""))[:20]
    standby_text = str(os.getenv("MEDIAPLAYER_STANDBY_TEXT", " MPlayer"))[:50]
    artist_track_separator = str(os.getenv("MEDIAPLAYER_ARTIST_TRACK_SEPARATOR", "  "))[
        :10
    ]

    # Validate color formats
    xdg_cache = os.path.expanduser(os.getenv("XDG_CACHE_HOME", "~/.cache"))
    wal_colors = load_pywal_colors(xdg_cache)
    default_artist = wal_colors.get("color4", "#FFFFFF")
    default_track = wal_colors.get("foreground", "#FFFFFF")
    default_progress = wal_colors.get("color2", default_artist)
    default_empty = wal_colors.get("color8", wal_colors.get("color0", "#666666"))
    default_time = wal_colors.get("foreground", "#FFFFFF")

    color_vars = {
        "artist_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_ARTIST_COLOR", ""), wal_colors, default_artist
        ),
        "track_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_TRACK_COLOR", ""), wal_colors, default_track
        ),
        "progress_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_PROGRESS_COLOR", ""),
            wal_colors,
            default_progress,
        ),
        "empty_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_EMPTY_COLOR", ""), wal_colors, default_empty
        ),
        "time_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_TIME_COLOR", ""), wal_colors, default_time
        ),
    }

    for var_name, color_value in color_vars.items():
        if not color_value.startswith("#") or len(color_value) not in [4, 7, 9]:
            print(f"WARNING: Invalid color format for {var_name}: {color_value}", file=sys.stderr)
            # Set safe fallback
            globals()[var_name] = "#FFFFFF"
        else:
            globals()[var_name] = color_value


def format_time(seconds: float) -> str:
    """Stable and consistent time formatter (HH:MM:SS or MM:SS)."""
    try:
        total = max(0, int(round(seconds)))
        h, m = divmod(total, 3600)
        m, s = divmod(m, 60)
        return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"
    except Exception:
        return "00:00"


def format_time_multiple_lines(seconds: float, playing: bool) -> str:
    """Multi-line timer with consistent alignment and no float artifacts."""
    try:
        total = max(0, int(round(seconds)))
        h, m = divmod(total, 3600)
        m, s = divmod(m, 60)
        icon = "󰼛" if playing else " "
        if h:
            return f"{icon}{h:02d}\n:{m:02d}\n:{s:02d}"
        else:
            return f"{icon}{m:02d}\n:{s:02d}"
    except Exception:
        return " \n:00"


def create_tooltip_text(
    artist,
    track,
    current_position_seconds,
    duration_seconds,
    p_name,
    loop_status=None,
    shuffle_status=None,
) -> str:
    tooltip = ""
    if artist or track:
        tooltip += f'<span foreground="{track_color}"><b>{track}</b></span>'
        tooltip += f'\n<span foreground="{artist_color}"><i>{artist}</i></span>\n'
        if duration_seconds > 0:
            progress = int((current_position_seconds / duration_seconds) * 20)
            bar = f'<span foreground="{progress_color}">{"█" * progress}</span><span foreground="{empty_color}">{"─" * (20 - progress)}</span>'
            tooltip += f'<span foreground="{time_color}">{format_time(current_position_seconds)}</span> {bar} <span foreground="{time_color}">{format_time(duration_seconds)}</span>'
            if loop_status is not None:
                loop_glyphs = {
                    "None": "󰑗 No Loop",
                    "Track": "󰑖 Loop Once",
                    "Playlist": "󰑘 Loop Playlist",
                }
                tooltip += f"\n<span foreground='{track_color}'>{loop_glyphs.get(loop_status, str(loop_status))}</span>"
            if shuffle_status is not None:
                shuffle_glyph = "󰒟 Shuffle On" if shuffle_status else "󰒞 Shuffle Off"
                tooltip += f"\n<span foreground='{track_color}'>{shuffle_glyph}</span>"
        tooltip += f"\n<span>{p_name}</span>"
    tooltip += (
        f"\n<span size='x-small' foreground='{track_color}'>"
        f"\n󰐎 click to play/pause\n scroll to seek\n󱥣 rightclick for options</span>"
    )
    return tooltip


def format_artist_track(artist, track, playing, max_length):
    prefix = prefix_playing if playing else prefix_paused
    prefix_separator = "  "
    full_length = len(artist + track)

    if track and not artist:
        if len(track) > max_length:
            track = track[:max_length].rstrip() + "…"
        output_text = f"{prefix}{prefix_separator}<b>{track}</b>"
    elif track and artist:
        artist = artist.split(",")[0].split("&")[0].strip()
        if full_length > max_length:
            artist_weight = 0.65
            artist_limit = min(int(max_length * artist_weight), len(artist))
            a_gain = max(0, artist_weight - (artist_limit / max_length))
            track_weight = 1 - artist_weight + a_gain
            track_limit = min(int(max_length * track_weight), len(track))
            t_gain = max(0, track_weight - (track_limit / max_length))

            if a_gain == 0 and t_gain > 0:
                gain = int(max_length * t_gain)
                artist_limit = artist_limit + gain
            elif a_gain > 0 and t_gain == 0:
                gain = int(max_length * a_gain)
                track_limit = track_limit + gain

            if len(artist) > artist_limit:
                artist = artist[:artist_limit].rstrip() + "…"
            if len(track) > track_limit:
                track = track[:track_limit].rstrip() + "…"

        output_text = f"{prefix}{prefix_separator}<i>{artist}</i>{artist_track_separator}<b>{track}</b>"
    else:
        if (
            current_player
            and hasattr(current_player, "props")
            and hasattr(current_player.props, "player_name")
        ):
            output_text = f"<b>{standby_text} {current_player.props.player_name}</b>"
        else:
            output_text = f"<b>{standby_text}</b>"
    return output_text


_last_metadata = {"track": "", "artist": "", "track_id": "", "duration": 0.0}
_last_valid_player = None
_last_seek_event = {"at": 0.0, "position": None}
_position_state = {
    "track_key": "",
    "anchor_position": 0.0,
    "anchor_monotonic": 0.0,
    "raw_position": 0.0,
    "timestamp": 0.0,
    "status": "Stopped",
    "rate": 1.0,
}
_persisted_position_state = {"track_key": "", "position": 0.0, "duration": 0.0, "wall_time": 0.0}


def write_output(current_player):
    """Get current state and write JSON output safely, even if Firefox changes song naturally."""
    global _last_metadata, _last_valid_player, _last_seek_event, _position_state, _persisted_position_state

    # --- Detect missing or invalid player ---
    if not current_player:
        output = {
            "text": standby_text,
            "class": "custom-nothing-playing",
            "alt": "",
            "tooltip": "",
        }
        emit_json_output(output)
        return

    # Firefox sometimes respawns MPRIS under a new instance name.
    try:
        _ = current_player.props.player_name
        _last_valid_player = current_player
    except Exception:
        if _last_valid_player:
            current_player = _last_valid_player
        else:
            return

    p_name = current_player.props.player_name

    # --- Position ---
    try:
        position_seconds = current_player.get_position() / 1e6
    except Exception:
        position_seconds = 0.0
    now_mono = time.monotonic()
    seek_position = _last_seek_event.get("position")
    seek_age = now_mono - float(_last_seek_event.get("at", 0.0))
    if (
        seek_position is not None
        and 0.0 <= seek_age <= 2.0
        and abs(float(seek_position) - position_seconds) > 1.0
    ):
        # Some MPRIS providers lag after jumps; trust the fresh seek event.
        position_seconds = max(0.0, float(seek_position))

    # --- Metadata & duration ---
    track = ""
    artist = ""
    track_id = ""
    media_url = ""
    duration_seconds = 0.0
    try:
        metadata = current_player.props.metadata
        if metadata:
            data = metadata.unpack()
            track = data.get("xesam:title", "") or ""
            artist = data.get("xesam:artist", [""])[0] if "xesam:artist" in data else ""
            track_id = str(data.get("mpris:trackid", "") or "")
            media_url = str(data.get("xesam:url", "") or "")
            duration_seconds = data.get("mpris:length", 0) / 1e6
    except Exception:
        pass

    ytdlp_duration = get_ytdlp_duration_seconds(media_url)
    # Trust MPRIS duration when it is present; only fallback to yt-dlp when missing.
    if ytdlp_duration and ytdlp_duration > 0 and duration_seconds <= 0:
        duration_seconds = ytdlp_duration

    raw_track = track
    raw_artist = artist
    raw_track_id = track_id

    player_status = current_player.props.status
    is_playing = player_status == "Playing"
    is_stopped = player_status == "Stopped"
    previous_raw_for_fallback = float(_position_state.get("raw_position", 0.0))
    recent_seek_to_start = (
        seek_position is not None
        and 0.0 <= seek_age <= 2.5
        and float(seek_position) <= 3.0
    )
    likely_track_rollover = (
        not raw_track
        and not raw_artist
        and not raw_track_id
        and is_playing
        and previous_raw_for_fallback > 5.0
        and position_seconds <= 3.0
    )

    raw_identity_present = bool(raw_track_id or raw_track or raw_artist)
    same_track_as_last = False
    if raw_track_id and _last_metadata["track_id"]:
        same_track_as_last = raw_track_id == _last_metadata["track_id"]
    elif raw_track and _last_metadata["track"]:
        same_track_as_last = raw_track == _last_metadata["track"]
        if raw_artist and _last_metadata["artist"]:
            same_track_as_last = same_track_as_last and raw_artist == _last_metadata["artist"]

    # Keep text strict during likely rollovers/jumps, but allow duration carry-over
    # on same-track transitions to avoid transient 0 timer flashes.
    allow_text_fallback = not (recent_seek_to_start or likely_track_rollover)
    allow_duration_fallback = not likely_track_rollover
    if recent_seek_to_start and not same_track_as_last:
        allow_duration_fallback = False

    # --- Firefox sometimes fails to update metadata; fallback to last known ---
    if allow_text_fallback and not track and _last_metadata["track"]:
        track = _last_metadata["track"]
    if allow_text_fallback and not artist and _last_metadata["artist"]:
        artist = _last_metadata["artist"]

    if (
        allow_duration_fallback
        and
        duration_seconds <= 0
        and _last_metadata["duration"] > 0
        and (not raw_identity_present or same_track_as_last)
    ):
        duration_seconds = _last_metadata["duration"]

    # --- Cache current metadata for next iteration ---
    if track or artist or duration_seconds > 0:
        cached_track_id = track_id
        if not cached_track_id and same_track_as_last:
            cached_track_id = _last_metadata["track_id"]
        _last_metadata = {
            "track": track,
            "artist": artist,
            "track_id": cached_track_id,
            "duration": duration_seconds if duration_seconds > 0 else 0.0,
        }

    try:
        playback_rate = float(current_player.get_rate())
    except Exception:
        try:
            playback_rate = float(current_player.props.rate)
        except Exception:
            playback_rate = 1.0
    if playback_rate <= 0:
        playback_rate = 1.0

    # --- If stopped, clear cache and output nothing (hide module) ---
    if is_stopped:
        _last_metadata = {"track": "", "artist": "", "track_id": "", "duration": 0.0}
        output = {
            "text": "",
            "class": "custom-stopped",
            "alt": "",
            "tooltip": "",
        }
        emit_json_output(output)
        save_runtime_position_state("", 0.0, 0.0)
        _position_state = {
            "track_key": "",
            "anchor_position": 0.0,
            "anchor_monotonic": 0.0,
            "raw_position": 0.0,
            "timestamp": 0.0,
            "status": "Stopped",
            "rate": 1.0,
        }
        return

    # --- Normalize raw values ---
    position_seconds = max(0.0, position_seconds)
    duration_seconds = max(0.0, round(duration_seconds, 2))
    if duration_seconds and position_seconds > duration_seconds:
        position_seconds = duration_seconds

    # --- Anchored playback clock ---
    now = now_mono
    track_key = f"{p_name}|{track_id}|{track}|{artist}|{duration_seconds:.3f}"
    raw_position = max(0.0, position_seconds)

    previous_track_key = str(_position_state.get("track_key", ""))
    previous_anchor_position = float(_position_state.get("anchor_position", 0.0))
    previous_anchor_monotonic = float(_position_state.get("anchor_monotonic", 0.0))
    previous_raw = float(_position_state.get("raw_position", 0.0))
    previous_status = str(_position_state.get("status", "Stopped"))
    previous_rate = float(_position_state.get("rate", 1.0) or 1.0)
    if previous_rate <= 0:
        previous_rate = 1.0

    if previous_track_key != track_key:
        anchor_position = raw_position
        anchor_monotonic = now
    else:
        predicted_from_anchor = previous_anchor_position
        if previous_status == "Playing":
            predicted_from_anchor += (
                max(0.0, now - previous_anchor_monotonic) * previous_rate
            )
        if duration_seconds > 0:
            predicted_from_anchor = min(duration_seconds, predicted_from_anchor)

        status_changed = player_status != previous_status
        raw_advanced = raw_position > (previous_raw + 0.2)
        raw_rewound = raw_position < (previous_raw - 0.5)
        jump_detected = abs(raw_position - predicted_from_anchor) > 2.0

        if status_changed:
            # On pause/resume transitions, never snap backward if MPRIS reports
            # a stale position (common with browser MPRIS providers).
            anchor_position = max(raw_position, predicted_from_anchor)
            anchor_monotonic = now
        elif raw_rewound or jump_detected:
            anchor_position = raw_position
            anchor_monotonic = now
        elif raw_advanced and is_playing:
            # Keep anchor aligned when source position progresses normally.
            anchor_position = raw_position
            anchor_monotonic = now
        elif not is_playing:
            # While paused, ignore minor raw jitter to prevent drift accumulation.
            anchor_position = previous_anchor_position
            anchor_monotonic = previous_anchor_monotonic
        else:
            # Preserve anchor while raw position stalls.
            anchor_position = previous_anchor_position
            anchor_monotonic = previous_anchor_monotonic

    if is_playing:
        position_seconds = anchor_position + (max(0.0, now - anchor_monotonic) * playback_rate)
    else:
        position_seconds = anchor_position

    position_seconds = max(0.0, round(position_seconds, 2))
    if duration_seconds and position_seconds > duration_seconds:
        position_seconds = duration_seconds

    _position_state = {
        "track_key": track_key,
        "anchor_position": anchor_position,
        "anchor_monotonic": anchor_monotonic,
        "raw_position": raw_position,
        "timestamp": now,
        "status": player_status,
        "rate": playback_rate,
    }
    _persisted_position_state = {
        "track_key": track_key,
        "position": position_seconds,
        "duration": duration_seconds,
        "wall_time": time.time(),
    }
    save_runtime_position_state(track_key, position_seconds, duration_seconds)

    # --- Compute time left ---
    time_left_seconds = (
        max(0.0, round(duration_seconds - position_seconds, 2))
        if duration_seconds
        else 0.0
    )

    # --- Loop & shuffle status (safe queries) ---
    try:
        loop_status = current_player.get_loop_status()
    except Exception:
        loop_status = None
    try:
        shuffle_status = current_player.get_shuffle()
    except Exception:
        shuffle_status = None

    # --- Tooltip ---
    tooltip_text = create_tooltip_text(
        artist,
        track,
        position_seconds,
        duration_seconds,
        p_name,
        loop_status,
        shuffle_status,
    )

    # --- Output ---
    output_data = {
        "text": escape(
            format_artist_track(artist, track, is_playing, max_length_module)
        ),
        "class": f"custom-{p_name}",
        "alt": format_time_multiple_lines(time_left_seconds, is_playing),
        "tooltip": escape(tooltip_text),
    }
    emit_json_output(output_data)


def on_play(player, status, manager):
    set_player(manager, player)


def on_playback_changed(player, status, manager):
    if status == "Playing":
        set_player(manager, player)
    write_output(player)


def on_metadata(player, metadata, manager):
    write_output(player)


def on_seeked(player, position, manager):
    global _last_seek_event
    try:
        seek_seconds = max(0.0, float(position) / 1e6)
    except Exception:
        seek_seconds = None
    _last_seek_event = {"at": time.monotonic(), "position": seek_seconds}
    write_output(player)


def on_player_appeared(manager, player, selected_players=None):
    if player is not None and (
        selected_players is None or player.name in selected_players
    ):
        p = init_player(manager, player)
        set_player(manager, p)
        if not hasattr(manager, "_polling") or not manager._polling:
            manager._polling = True
            # Store timer ID for potential cleanup
            global _timer_id
            if _timer_id:
                GLib.source_remove(_timer_id)
            _timer_id = GLib.timeout_add(950, timer_tick, manager)


def on_player_vanished(manager, player, loop):
    global current_player, _timer_id
    p_name = player.props.player_name

    if current_player and current_player.props.player_name == p_name:
        if manager.props.players:
            set_player(manager, manager.props.players[0])
        else:
            current_player = None
            # Stop timer when no players left to prevent memory leaks
            if _timer_id:
                GLib.source_remove(_timer_id)
                _timer_id = None
                manager._polling = False
            output = {
                "text": standby_text,
                "class": "custom-nothing-playing",
                "alt": "",
                "tooltip": "",
            }
            emit_json_output(output)


def init_player(manager, name):
    player = Playerctl.Player.new_from_name(name)
    player.connect("playback-status", on_playback_changed, manager)
    player.connect("playback-status::playing", on_play, manager)
    player.connect("metadata", on_metadata, manager)
    player.connect("seeked", on_seeked, manager)
    manager.manage_player(player)
    return player


def timer_tick(manager):
    """Called every second to update display - with memory leak prevention"""
    # Stop timer if no players are available
    if not manager.props.players or not current_player:
        global _timer_id
        _timer_id = None
        manager._polling = False
        return False  # This stops the timer

    if current_player and current_player.props.status == "Playing":
        write_output(current_player)
    return True  # Continue the timer


def set_player(manager, player):
    global current_player
    if current_player and current_player.props.player_name != player.props.player_name:
        try:
            current_player.pause()
        except Exception:
            pass
    current_player = player
    manager.move_player_to_top(player)
    write_output(player)


def signal_handler(sig, frame):
    global _timer_id
    if sig == signal.SIGPIPE:
        os._exit(0)
    # Clean up timer on exit
    if _timer_id:
        GLib.source_remove(_timer_id)
    sys.exit(0)


def parse_arguments():
    parser = argparse.ArgumentParser(description="A media player status tool")
    parser.add_argument("--players", nargs="*", type=str)
    parser.add_argument("--player", type=str)
    return parser.parse_args()


def escape(string):
    return string.replace("&", "&amp;")


def main():
    global \
        prefix_playing, \
        prefix_paused, \
        max_length_module, \
        standby_text, \
        artist_track_separator
    global artist_color, track_color, progress_color, empty_color, time_color, _timer_id
    global _runtime_state_file, _persisted_position_state, _recover_max_age_seconds
    global _ytdlp_timeout_seconds

    xdg_state = os.path.expanduser(os.getenv("XDG_STATE_HOME", "~/.local/state"))
    xdg_cache = os.path.expanduser(os.getenv("XDG_CACHE_HOME", "~/.cache"))
    xdg_runtime = os.path.expanduser(
        os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    )
    _runtime_state_file = os.path.join(xdg_runtime, "hypr", "mediaplayer-position.json")
    _persisted_position_state = load_runtime_position_state()
    _recover_max_age_seconds = get_recover_max_age_seconds()
    _ytdlp_timeout_seconds = get_ytdlp_timeout_seconds()
    config_file = os.path.join(xdg_state, "hypr", "config")
    if os.path.exists(config_file):
        load_env_file(config_file)

    # Validate all configuration values
    validate_config()

    players = os.getenv("MEDIAPLAYER_PLAYERS", None)
    if players:
        players = players.split(",")

    arguments = parse_arguments()

    logging.basicConfig(stream=sys.stderr, level=logging.WARNING, format="%(message)s")

    manager = Playerctl.PlayerManager()
    choose = False
    if not (arguments.players or arguments.player) and not players:
        players = [name.name for name in manager.props.player_names]
    else:
        choose = True
        if arguments.players:
            players = arguments.players
        elif arguments.player:
            players = [arguments.player]

    loop = GLib.MainLoop()

    manager.connect(
        "name-appeared",
        lambda *args: on_player_appeared(*args, players if choose else None),
    )
    manager.connect("player-vanished", lambda *args: on_player_vanished(*args, loop))

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGPIPE, signal_handler)

    found = [None] * len(players)
    for player in manager.props.player_names:
        if (
            players is not None and player.name not in players
        ) or player.name == "plasma-browser-integration":
            continue
        p = init_player(manager, player)
        found[players.index(player.name)] = p

    if found:
        found = list(filter(lambda x: x is not None, found))
        if found:
            try:
                p = next(player for player in found if player.props.status == "Playing")
            except StopIteration:
                p = found[0]
            set_player(manager, p)
        else:
            write_output(current_player)
    else:
        write_output(current_player)

    if manager.props.players:
        manager._polling = True
        _timer_id = GLib.timeout_add_seconds(1, timer_tick, manager)

    try:
        loop.run()
    except KeyboardInterrupt:
        print("INFO: Received interrupt, shutting down...", file=sys.stderr)
    finally:
        # Final cleanup
        if _timer_id:
            GLib.source_remove(_timer_id)


if __name__ == "__main__":
    main()
