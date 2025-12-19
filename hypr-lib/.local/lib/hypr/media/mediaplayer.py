#!/usr/bin/env python3
import os
import sys

import gi

gi.require_version("Playerctl", "2.0")
import argparse
import json
import logging
import signal

from gi.repository import GLib, Playerctl

players_data = {}
current_player = None
_timer_id = None  # Track the timer source ID


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
    color_vars = {
        "artist_color": os.getenv(
            "MEDIAPLAYER_TOOLTIP_ARTIST_COLOR", "#" + os.getenv("dcol_3xa8", "FFFFFF")
        ),
        "track_color": os.getenv(
            "MEDIAPLAYER_TOOLTIP_TRACK_COLOR", "#" + os.getenv("dcol_txt1", "FFFFFF")
        ),
        "progress_color": os.getenv(
            "MEDIAPLAYER_TOOLTIP_PROGRESS_COLOR", "#" + os.getenv("dcol_pry4", "FFFFFF")
        ),
        "empty_color": os.getenv(
            "MEDIAPLAYER_TOOLTIP_EMPTY_COLOR", "#" + os.getenv("dcol_1xa3", "FFFFFF")
        ),
        "time_color": os.getenv(
            "MEDIAPLAYER_TOOLTIP_TIME_COLOR", "#" + os.getenv("dcol_txt1", "FFFFFF")
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


_last_metadata = {"track": "", "artist": "", "duration": 0.0}
_last_valid_player = None


def write_output(current_player):
    """Get current state and write JSON output safely, even if Firefox changes song naturally."""
    global _last_metadata, _last_valid_player

    # --- Detect missing or invalid player ---
    if not current_player:
        output = {
            "text": standby_text,
            "class": "custom-nothing-playing",
            "alt": "",
            "tooltip": "",
        }
        sys.stdout.write(json.dumps(output) + "\n")
        sys.stdout.flush()
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

    # --- Metadata & duration ---
    track = ""
    artist = ""
    duration_seconds = 0.0
    try:
        metadata = current_player.props.metadata
        if metadata:
            data = metadata.unpack()
            track = data.get("xesam:title", "") or ""
            artist = data.get("xesam:artist", [""])[0] if "xesam:artist" in data else ""
            duration_seconds = data.get("mpris:length", 0) / 1e6
    except Exception:
        pass

    # --- Firefox sometimes fails to update metadata; fallback to last known ---
    if not track and _last_metadata["track"]:
        track = _last_metadata["track"]
    if not artist and _last_metadata["artist"]:
        artist = _last_metadata["artist"]
    if duration_seconds <= 0 and _last_metadata["duration"] > 0:
        duration_seconds = _last_metadata["duration"]

    # --- Cache current metadata for next iteration ---
    if track or artist or duration_seconds > 0:
        _last_metadata = {
            "track": track,
            "artist": artist,
            "duration": duration_seconds,
        }

    player_status = current_player.props.status
    is_playing = player_status == "Playing"
    is_stopped = player_status == "Stopped"

    # --- If stopped, clear cache and output nothing (hide module) ---
    if is_stopped:
        _last_metadata = {"track": "", "artist": "", "duration": 0.0}
        output = {
            "text": "",
            "class": "custom-stopped",
            "alt": "",
            "tooltip": "",
        }
        sys.stdout.write(json.dumps(output) + "\n")
        sys.stdout.flush()
        return

    # --- Normalize values to avoid float drift ---
    position_seconds = max(0.0, round(position_seconds, 2))
    duration_seconds = max(0.0, round(duration_seconds, 2))
    if duration_seconds and position_seconds > duration_seconds:
        position_seconds = duration_seconds

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

    sys.stdout.write(json.dumps(output_data, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def on_play(player, status, manager):
    set_player(manager, player)


def on_playback_changed(player, status, manager):
    if status == "Playing":
        set_player(manager, player)
    write_output(player)


def on_metadata(player, metadata, manager):
    write_output(player)


def on_seeked(player, position, manager):
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
            sys.stdout.write(json.dumps(output) + "\n")
            sys.stdout.flush()


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
    # Clean up timer on exit
    if _timer_id:
        GLib.source_remove(_timer_id)
    sys.stdout.write("\n")
    sys.stdout.flush()
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

    xdg_state = os.path.expanduser(os.getenv("XDG_STATE_HOME", "~/.local/state"))
    xdg_cache = os.path.expanduser(os.getenv("XDG_CACHE_HOME", "~/.cache"))
    config_file = os.path.join(xdg_state, "hypr", "config")
    colors_file = os.path.join(xdg_cache, "hypr/wall.dcol")
    if os.path.exists(config_file):
        load_env_file(config_file)
    if os.path.exists(colors_file):
        load_env_file(colors_file)

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
