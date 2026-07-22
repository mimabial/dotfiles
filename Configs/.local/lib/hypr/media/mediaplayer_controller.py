#!/usr/bin/env python3
import logging
import os
import gi
import signal
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

gi.require_version("Playerctl", "2.0")

from gi.repository import GLib, Playerctl
from pyutils.shell_env import load_shell_assignments
from mediaplayer_browser import (
    get_ytdlp_timeout_seconds,
    set_ytdlp_timeout_seconds,
    title_looks_live,
    youtube_position_is_untrusted,
)
from mediaplayer_actions import (
    read_active_player_state,
    state_path,
    write_active_player_state,
)
from mediaplayer_policy import (
    build_track_identity_key,
    read_player_metadata,
    resolve_browser_metadata_fallbacks,
    resolve_metadata_duration,
)
from mediaplayer_ui import (
    create_tooltip_text,
    emit_json_output,
    escape,
    format_artist_track,
    format_live_multiple_lines,
    format_live_single_line,
    format_time_multiple_lines,
    format_time_single_line,
    validate_ui_config,
)

current_player = None
_timer_id = None  # Track the timer source ID
UI_CONFIG = None
ALT_MODE = False
_active_player_cache = {"mtime": -1.0, "value": ""}


def cached_active_player_state() -> str:
    """Return the active player from state, re-reading only when mtime changes."""
    try:
        mtime = state_path().stat().st_mtime
    except OSError:
        _active_player_cache["mtime"] = -1.0
        _active_player_cache["value"] = ""
        return ""
    if mtime != _active_player_cache["mtime"]:
        _active_player_cache["value"] = read_active_player_state()
        _active_player_cache["mtime"] = mtime
    return _active_player_cache["value"]


def player_state_name(player) -> str:
    if player is None:
        return ""
    try:
        return str(player.props.player_instance or player.props.player_name or "")
    except Exception:
        return ""


def player_matches_name(player, name: str) -> bool:
    if not name:
        return False
    if player_state_name(player) == name:
        return True
    try:
        return str(player.props.player_name or "") == name
    except Exception:
        return False


def is_current_player(player) -> bool:
    current_name = player_state_name(current_player)
    return bool(current_name and current_name == player_state_name(player))


def preferred_player(players):
    managed = list(players or [])
    selected = cached_active_player_state()
    if selected:
        for player in managed:
            if not player_matches_name(player, selected):
                continue
            try:
                if player.props.status != "Stopped":
                    return player
            except Exception:
                return player
            break
    for player in managed:
        try:
            if player.props.status == "Playing":
                return player
        except Exception:
            continue
    return managed[0] if managed else None


def load_env_file(filepath: str) -> None:
    try:
        for key, value in load_shell_assignments(filepath).items():
            os.environ[key] = value
    except FileNotFoundError:
        return
    except OSError as e:
        print(f"ERROR: Error loading environment file {filepath}: {e}", file=sys.stderr)


_last_metadata = {
    "track": "",
    "artist": "",
    "track_id": "",
    "media_url": "",
    "duration": 0.0,
    "live_status": "",
}
_last_valid_player = None
_last_seek_event = {"at": 0.0, "position": None}
_position_state = {
    "track_key": "",
    "raw_position": 0.0,
    "timestamp": 0.0,
    "status": "Stopped",
    "rate": 1.0,
}

def write_output(current_player):
    """Get current state and write JSON output safely, even if Firefox changes song naturally."""
    global _last_metadata, _last_valid_player, _last_seek_event, _position_state

    # --- Detect missing or invalid player ---
    if not current_player:
        output = {
            "text": UI_CONFIG.standby_text if UI_CONFIG else " MPlayer",
            "class": "nothing-playing",
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

    player_status = current_player.props.status
    is_playing = player_status == "Playing"
    is_stopped = player_status == "Stopped"
    raw_metadata = resolve_metadata_duration(
        read_player_metadata(current_player),
        _last_metadata,
    )
    resolved_metadata, _last_metadata = resolve_browser_metadata_fallbacks(
        raw_metadata,
        player_status=player_status,
        position_seconds=position_seconds,
        seek_position=seek_position,
        seek_age=seek_age,
        last_metadata=_last_metadata,
        position_state=_position_state,
    )
    track = resolved_metadata.track
    artist = resolved_metadata.artist
    track_id = resolved_metadata.track_id
    media_url = resolved_metadata.media_url
    duration_seconds = resolved_metadata.duration_seconds
    is_live_stream = resolved_metadata.is_live_stream

    try:
        playback_rate = float(current_player.get_rate())
    except Exception:
        try:
            playback_rate = float(current_player.props.rate)
        except Exception:
            playback_rate = 1.0
    if playback_rate <= 0:
        playback_rate = 1.0

    # --- If stopped, treat as no-player (mpd-mpris idle daemon, etc.) ---
    if is_stopped:
        _last_metadata = {
            "track": "",
            "artist": "",
            "track_id": "",
            "media_url": "",
            "duration": 0.0,
            "live_status": "",
        }
        output = {
            "text": UI_CONFIG.standby_text if UI_CONFIG else " MPlayer",
            "class": "nothing-playing",
            "alt": "",
            "tooltip": "",
        }
        emit_json_output(output)
        _position_state = {
            "track_key": "",
            "raw_position": 0.0,
            "timestamp": 0.0,
            "status": "Stopped",
            "rate": 1.0,
        }
        return

    # --- Normalize raw values ---
    reported_position_seconds = max(0.0, position_seconds)
    duration_seconds = max(0.0, round(duration_seconds, 2))

    if (
        not is_live_stream
        and resolved_metadata.is_youtube
        and not resolved_metadata.ytdlp_live_status
        and title_looks_live(track)
    ):
        is_live_stream = True
        duration_seconds = 0.0

    track_key = build_track_identity_key(p_name, track_id, media_url, track, artist)
    previous_track_key = str(_position_state.get("track_key", ""))
    previous_raw = float(_position_state.get("raw_position", 0.0))
    recent_seek = seek_position is not None and 0.0 <= seek_age <= 2.5
    recent_seek_to_end = (
        recent_seek
        and duration_seconds > 0
        and float(seek_position) >= max(0.0, duration_seconds - 5.0)
    )
    position_untrusted = youtube_position_is_untrusted(
        resolved_metadata=resolved_metadata,
        raw_metadata=raw_metadata,
        reported_position_seconds=reported_position_seconds,
        duration_seconds=duration_seconds,
        is_playing=is_playing,
        recent_seek_to_end=recent_seek_to_end,
        previous_track_key=previous_track_key,
        current_track_key=track_key,
        previous_raw_position=previous_raw,
    )
    if position_untrusted:
        if previous_track_key == track_key:
            position_seconds = previous_raw
        else:
            position_seconds = 0.0
    else:
        position_seconds = reported_position_seconds

    position_seconds = max(0.0, round(position_seconds, 2))
    if duration_seconds > 0 and position_seconds > duration_seconds:
        position_seconds = duration_seconds

    _position_state = {
        "track_key": track_key,
        "raw_position": position_seconds,
        "timestamp": now_mono,
        "status": player_status,
        "rate": playback_rate,
    }

    # --- Compute displayed time ---
    countdown_display = bool(duration_seconds and not is_live_stream and not position_untrusted)
    time_display_seconds = (
        max(0.0, round(duration_seconds - position_seconds, 2))
        if countdown_display
        else max(0.0, round(position_seconds, 2))
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
        UI_CONFIG,
        is_live_stream=is_live_stream,
        loop_status=loop_status,
        shuffle_status=shuffle_status,
    )

    # --- Output ---
    output_data = {
        "text": escape(
            format_artist_track(
                artist,
                track,
                is_playing,
                UI_CONFIG,
                standby_player_name=p_name,
            )
        ),
        "class": ["playing", p_name],
        "alt": (
            (format_live_single_line if ALT_MODE else format_live_multiple_lines)(
                is_playing
            )
            if is_live_stream
            else (format_time_single_line if ALT_MODE else format_time_multiple_lines)(
                time_display_seconds,
                is_playing,
                countdown=countdown_display,
            )
        ),
        "tooltip": escape(tooltip_text),
    }
    emit_json_output(output_data)


def on_play(player, status, manager):
    if is_current_player(player):
        write_output(player)


def on_playback_changed(player, status, manager):
    if is_current_player(player):
        write_output(player)


def on_metadata(player, metadata, manager):
    if is_current_player(player):
        write_output(player)


def on_seeked(player, position, manager):
    global _last_seek_event
    if not is_current_player(player):
        return
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
        if current_player is None:
            set_player(manager, p)
        if not hasattr(manager, "_polling") or not manager._polling:
            manager._polling = True
            global _timer_id
            if _timer_id:
                GLib.source_remove(_timer_id)
            _timer_id = GLib.timeout_add_seconds(1, timer_tick, manager)


def on_player_vanished(manager, player, loop):
    global current_player, _timer_id, _last_valid_player
    if _last_valid_player is player:
        _last_valid_player = None
    if is_current_player(player):
        remaining = [
            candidate
            for candidate in manager.props.players
            if player_state_name(candidate) != player_state_name(player)
        ]
        replacement = preferred_player(remaining)
        if replacement:
            set_player(manager, replacement)
        else:
            current_player = None
            if _timer_id:
                GLib.source_remove(_timer_id)
                _timer_id = None
                manager._polling = False
            output = {
                "text": UI_CONFIG.standby_text if UI_CONFIG else " MPlayer",
                "class": "nothing-playing",
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
    players = list(manager.props.players or [])
    if not players:
        global _timer_id
        _timer_id = None
        manager._polling = False
        return False

    selected_name = cached_active_player_state()
    selected_player = next(
        (player for player in players if player_matches_name(player, selected_name)),
        None,
    )
    try:
        selected_stopped = selected_player is not None and selected_player.props.status == "Stopped"
    except Exception:
        selected_stopped = False
    if selected_player and not selected_stopped and not is_current_player(selected_player):
        set_player(manager, selected_player)
    elif current_player is None or selected_stopped:
        set_player(manager, preferred_player(players))

    if current_player and current_player.props.status == "Playing":
        write_output(current_player)
    return True


def set_player(manager, player):
    global current_player
    if player is None:
        return
    if player is not current_player:
        current_player = player
        manager.move_player_to_top(player)
        write_active_player_state(player_state_name(player))
    write_output(player)


def signal_handler(sig, frame):
    global _timer_id
    if sig == signal.SIGPIPE:
        os._exit(0)
    # Clean up timer on exit
    if _timer_id:
        GLib.source_remove(_timer_id)
    sys.exit(0)




def run(arguments):
    global _timer_id, UI_CONFIG, ALT_MODE

    xdg_state = os.path.expanduser(os.getenv("XDG_STATE_HOME", "~/.local/state"))
    set_ytdlp_timeout_seconds(get_ytdlp_timeout_seconds())
    state_dir = os.path.join(xdg_state, "hypr")
    load_env_file(os.path.join(state_dir, "staterc"))
    load_env_file(os.path.join(state_dir, "env-overrides"))

    UI_CONFIG = validate_ui_config()
    ALT_MODE = getattr(arguments, "alt", False)

    players = os.getenv("MEDIAPLAYER_PLAYERS", None)
    if players:
        players = players.split(",")

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
        if players is not None and player.name not in players:
            continue
        p = init_player(manager, player)
        found[players.index(player.name)] = p

    if found:
        found = list(filter(lambda x: x is not None, found))
        if found:
            set_player(manager, preferred_player(found))
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
        if _timer_id:
            GLib.source_remove(_timer_id)
