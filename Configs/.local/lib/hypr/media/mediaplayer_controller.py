#!/usr/bin/env python3
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass, field

import gi

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

gi.require_version("Playerctl", "2.0")

from gi.repository import Gio, GLib, Playerctl
from mediaplayer_actions import (
    player_name_matches,
    read_active_player_state,
    active_player_state_path,
    write_active_player_state,
)
from mediaplayer_browser import (
    get_ytdlp_timeout_seconds,
    on_media_info_ready,
    set_ytdlp_timeout_seconds,
)
from mediaplayer_policy import (
    PlaybackSnapshot,
    PlaybackState,
    ResolvedPlayback,
    read_player_metadata,
    resolve_playback,
)
from mediaplayer_ui import (
    DEFAULT_STANDBY_TEXT,
    create_tooltip_text,
    emit_json_output,
    escape_markup_text,
    format_artist_track,
    format_live_multiple_lines,
    format_live_single_line,
    format_state_icon,
    format_time_multiple_lines,
    format_time_single_line,
    validate_ui_config,
)
from pyutils.shell_env import load_shell_assignments
from pyutils.xdg_base_dirs import xdg_state_home


@dataclass
class MediaPlayerControllerState:
    current_player: object | None = None
    current_player_name: str = ""
    last_valid_player: object | None = None
    playback_clock_id: int | None = None
    active_player_monitor: object | None = None
    main_loop: object | None = None
    shutdown_requested: bool = False
    ui_config: object | None = None
    alt_mode: bool = False
    icon_mode: bool = False
    active_player_mtime: float = -1.0
    active_player_value: str = ""
    playback: PlaybackState = field(default_factory=PlaybackState)


STATE = MediaPlayerControllerState()
PLAYBACK_CLOCK_INTERVAL_SECONDS = 1
LOOP_STATUS_LABELS = {
    Playerctl.LoopStatus.NONE: "None",
    Playerctl.LoopStatus.TRACK: "Track",
    Playerctl.LoopStatus.PLAYLIST: "Playlist",
}


def current_player_is_playing() -> bool:
    try:
        return STATE.current_player is not None and STATE.current_player.props.status == "Playing"
    except Exception:
        return False


def stop_playback_clock() -> None:
    clock_id = STATE.playback_clock_id
    STATE.playback_clock_id = None
    if clock_id:
        GLib.source_remove(clock_id)


def playback_clock_tick() -> bool:
    if not current_player_is_playing():
        STATE.playback_clock_id = None
        return False
    emit_player_state(STATE.current_player)
    return True


def sync_playback_clock() -> None:
    if not current_player_is_playing():
        stop_playback_clock()
    elif STATE.playback_clock_id is None:
        STATE.playback_clock_id = GLib.timeout_add_seconds(PLAYBACK_CLOCK_INTERVAL_SECONDS, playback_clock_tick)


def cached_active_player_state() -> str:
    try:
        mtime = active_player_state_path().stat().st_mtime
    except OSError:
        STATE.active_player_mtime = -1.0
        STATE.active_player_value = ""
        return ""
    if mtime != STATE.active_player_mtime:
        STATE.active_player_value = read_active_player_state()
        STATE.active_player_mtime = mtime
    return STATE.active_player_value


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
    return bool(
        player is STATE.current_player
        or (
            STATE.current_player_name
            and STATE.current_player_name == player_state_name(player)
        )
    )


def preferred_player(players):
    managed = list(players or [])
    selected = cached_active_player_state()
    selected_player = None
    selected_status = None
    if selected:
        for player in managed:
            if not player_matches_name(player, selected):
                continue
            selected_player = player
            try:
                selected_status = player.props.status
                if selected_status == "Playing":
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
    if selected_player is not None and selected_status != "Stopped":
        return selected_player
    return managed[0] if managed else None


def load_env_file(filepath: str) -> None:
    try:
        for key, value in load_shell_assignments(filepath).items():
            os.environ[key] = value
    except FileNotFoundError:
        return
    except OSError as error:
        print(
            f"ERROR: Error loading environment file {filepath}: {error}",
            file=sys.stderr,
        )


def emit_standby(player_name: str = "") -> None:
    text = STATE.ui_config.standby_text if STATE.ui_config else DEFAULT_STANDBY_TEXT
    emit_json_output(
        {
            "text": escape_markup_text(text),
            "class": ["stopped", player_name] if player_name else "nothing-playing",
            "alt": format_state_icon("Stopped") if STATE.icon_mode else "",
            "tooltip": "",
        }
    )


def recover_player(player):
    try:
        _ = player.props.player_name
    except Exception:
        fallback = STATE.last_valid_player
        if (
            player is STATE.current_player
            and fallback is not None
            and player_state_name(fallback) == STATE.current_player_name
        ):
            return fallback
        return None
    STATE.last_valid_player = player
    if player is STATE.current_player:
        STATE.current_player_name = player_state_name(player)
    return player


def read_playback_snapshot(player) -> PlaybackSnapshot:
    try:
        position_seconds = player.get_position() / 1e6
    except Exception:
        position_seconds = 0.0
    return PlaybackSnapshot(
        player_name=player.props.player_name,
        status=player.props.status,
        reported_position_seconds=position_seconds,
        metadata=read_player_metadata(player),
        observed_at=time.monotonic(),
        loop_status=LOOP_STATUS_LABELS.get(player.props.loop_status),
        shuffle_status=bool(player.props.shuffle),
    )


def emit_playback(playback: ResolvedPlayback) -> None:
    metadata = playback.metadata
    tooltip_text = create_tooltip_text(
        metadata.artist,
        metadata.track,
        playback.position_seconds,
        metadata.duration_seconds,
        playback.player_name,
        STATE.ui_config,
        is_live_stream=metadata.is_live_stream,
        loop_status=playback.loop_status,
        shuffle_status=playback.shuffle_status,
    )
    if metadata.is_live_stream:
        alt_formatter = (
            format_live_single_line if STATE.alt_mode else format_live_multiple_lines
        )
        alt = alt_formatter(playback.is_playing)
    else:
        alt_formatter = (
            format_time_single_line if STATE.alt_mode else format_time_multiple_lines
        )
        alt = alt_formatter(
            playback.time_display_seconds,
            playback.is_playing,
            countdown=playback.countdown_display,
        )
    if STATE.icon_mode:
        alt = format_state_icon(playback.status)
    emit_json_output(
        {
            "text": format_artist_track(
                metadata.artist,
                metadata.track,
                playback.is_playing,
                STATE.ui_config,
                standby_player_name=playback.player_name,
            ),
            "class": [playback.status.lower(), playback.player_name],
            "alt": alt,
            "tooltip": tooltip_text,
        }
    )


def emit_player_state(player) -> None:
    if player is None:
        emit_standby()
        return
    player = recover_player(player)
    if player is None:
        return
    snapshot = read_playback_snapshot(player)
    if snapshot.status == "Stopped":
        STATE.playback.reset()
        emit_standby(snapshot.player_name)
        return
    emit_playback(resolve_playback(snapshot, STATE.playback))


def follow_preferred_player(manager) -> None:
    selected_player = preferred_player(manager.props.players)
    if selected_player is not None and not is_current_player(selected_player):
        set_player(manager, selected_player)


def watch_active_player_state(manager) -> None:
    monitor = Gio.File.new_for_path(str(active_player_state_path())).monitor_file(Gio.FileMonitorFlags.NONE, None)
    monitor.connect("changed", lambda *_: follow_preferred_player(manager))
    STATE.active_player_monitor = monitor


def on_playback_changed(player, status, manager):
    selected_player = preferred_player(manager.props.players)
    if selected_player is not None and not is_current_player(selected_player):
        set_player(manager, selected_player)
    elif is_current_player(player):
        emit_player_state(player)
    sync_playback_clock()


def on_metadata(player, metadata, manager):
    if is_current_player(player):
        emit_player_state(player)


def on_seeked(player, position, manager):
    if not is_current_player(player):
        return
    try:
        seek_seconds = max(0.0, float(position) / 1e6)
    except Exception:
        seek_seconds = None
    STATE.playback.record_seek(seek_seconds, time.monotonic())
    emit_player_state(player)


def on_player_appeared(manager, player, selected_players=None):
    if player is not None and (
        selected_players is None
        or any(player_name_matches(player.name, name) for name in selected_players)
    ):
        init_player(manager, player)
        follow_preferred_player(manager)


def on_player_vanished(manager, player, loop):
    if STATE.last_valid_player is player:
        STATE.last_valid_player = None
    if not is_current_player(player):
        return
    remaining = [
        candidate
        for candidate in manager.props.players
        if player_state_name(candidate) != player_state_name(player)
    ]
    replacement = preferred_player(remaining)
    if replacement:
        set_player(manager, replacement)
        return
    STATE.current_player = None
    STATE.current_player_name = ""
    STATE.playback.reset()
    stop_playback_clock()
    emit_standby()


def init_player(manager, name):
    player = Playerctl.Player.new_from_name(name)
    player.connect("playback-status", on_playback_changed, manager)
    player.connect("metadata", on_metadata, manager)
    player.connect("seeked", on_seeked, manager)
    manager.manage_player(player)
    return player


def set_player(manager, player):
    if player is None:
        return
    if player is not STATE.current_player:
        STATE.current_player = player
        STATE.current_player_name = player_state_name(player)
        manager.move_player_to_top(player)
        write_active_player_state(STATE.current_player_name)
    emit_player_state(player)
    sync_playback_clock()


def signal_handler(received_signal, frame):
    if received_signal == signal.SIGPIPE:
        os._exit(0)
    if STATE.main_loop is None:
        os._exit(0)
    if not STATE.shutdown_requested:
        STATE.shutdown_requested = True
        GLib.idle_add(STATE.main_loop.quit)


def resolve_players(arguments, manager):
    players = os.getenv("MEDIAPLAYER_PLAYERS", None)
    if players:
        players = players.split(",")
    if arguments.players:
        return arguments.players, True
    if arguments.player:
        return [arguments.player], True
    if players:
        return players, True
    return [name.name for name in manager.props.player_names], False


def watch_media_players(arguments):
    STATE.shutdown_requested = False

    xdg_state = str(xdg_state_home())
    set_ytdlp_timeout_seconds(get_ytdlp_timeout_seconds())
    state_dir = os.path.join(xdg_state, "hypr")
    load_env_file(os.path.join(state_dir, "staterc"))
    load_env_file(os.path.join(state_dir, "env-overrides"))

    STATE.ui_config = validate_ui_config()
    STATE.alt_mode = getattr(arguments, "alt", False)
    STATE.icon_mode = getattr(arguments, "icon", False)

    logging.basicConfig(
        stream=sys.stderr,
        level=logging.WARNING,
        format="%(message)s",
    )

    manager = Playerctl.PlayerManager()
    players, restrict_to_selected_players = resolve_players(arguments, manager)

    loop = GLib.MainLoop()
    STATE.main_loop = loop

    manager.connect(
        "name-appeared",
        lambda *args: on_player_appeared(*args, players if restrict_to_selected_players else None),
    )
    manager.connect("player-vanished", lambda *args: on_player_vanished(*args, loop))

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGPIPE, signal_handler)

    managed_players = []
    for player in manager.props.player_names:
        if not any(player_name_matches(player.name, name) for name in players):
            continue
        managed_players.append(init_player(manager, player))

    if managed_players:
        set_player(manager, preferred_player(managed_players))
    else:
        emit_player_state(STATE.current_player)

    sync_playback_clock()
    watch_active_player_state(manager)
    on_media_info_ready(lambda: emit_player_state(STATE.current_player))

    try:
        loop.run()
    except KeyboardInterrupt:
        print("INFO: Received interrupt, shutting down...", file=sys.stderr)
    finally:
        STATE.main_loop = None
        stop_playback_clock()
