#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

from gi.repository import GLib

from mediaplayer_presenter import mpris_call, show_player


ACTIONS = {
    "play-pause": ("play-pause",),
    "next": ("next",),
    "previous": ("previous",),
    "cycle-next": (),
    "cycle-previous": (),
    "stop": ("stop",),
    "shuffle": ("shuffle", "toggle"),
    "repeat": ("loop", "Track"),
    "loop": ("loop", "Playlist"),
    "disable-loop": ("loop", "None"),
    "show-player": (),
}

PLAYER_CYCLE_STEPS = {
    "cycle-next": 1,
    "cycle-previous": -1,
}

CAPABILITY_BY_ACTION = {
    "next": "CanGoNext",
    "previous": "CanGoPrevious",
}

PROPERTY_BY_ACTION = {
    "shuffle": "Shuffle",
    "repeat": "LoopStatus",
    "loop": "LoopStatus",
    "disable-loop": "LoopStatus",
}

def active_player_state_path() -> Path:
    if os.environ.get("HYPR_STATE_HOME"):
        return Path(os.environ["HYPR_STATE_HOME"]) / "mediaplayer.json"
    xdg_state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return xdg_state / "hypr" / "mediaplayer.json"


def write_active_player_state(player_name: str) -> None:
    if not player_name:
        return
    if read_active_player_state() == player_name:
        return
    path = active_player_state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".tmp.{os.getpid()}")
    try:
        tmp.write_text(json.dumps({"player": player_name, "updated_at": time.time()}) + "\n")
        tmp.replace(path)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def read_active_player_state() -> str:
    try:
        data = json.loads(active_player_state_path().read_text())
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return ""
    return str(data.get("player") or "")


def run_playerctl_command(args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return proc.returncode, proc.stdout.strip()


def available_players() -> list[str]:
    code, output = run_playerctl_command(["playerctl", "-l"])
    if code != 0 or not output:
        return []
    players = [line.strip() for line in output.splitlines() if line.strip()]
    configured = [name.strip() for name in os.environ.get("MEDIAPLAYER_PLAYERS", "").split(",") if name.strip()]
    if not configured:
        return players
    return [
        player
        for player in players
        if any(player_name_matches(player, name) for name in configured)
    ]


def player_status(player: str) -> str:
    _, output = run_playerctl_command(["playerctl", "-p", player, "status"])
    return output


def player_name_matches(player: str, requested: str) -> bool:
    return player == requested or player.startswith(f"{requested}.")


def resolve_player(explicit_player: str = "") -> str:
    players = available_players()
    if not players:
        return ""
    if explicit_player:
        for player in players:
            if player_name_matches(player, explicit_player):
                return player

    saved = read_active_player_state()
    if saved:
        for player in players:
            if player_name_matches(player, saved):
                return player

    for player in players:
        if player_status(player) == "Playing":
            return player
    return players[0]


def cycle_player(step: int) -> int:
    players = available_players()
    if not players:
        return 0

    statuses = {player: player_status(player) for player in players}
    active = [player for player in players if statuses[player] != "Stopped"]
    pool = active if active else players

    selected = read_active_player_state()
    current = ""
    if selected in pool:
        current = selected
    elif selected:
        current = next(
            (player for player in pool if player_name_matches(player, selected)),
            "",
        )

    if not current:
        current = next(
            (player for player in pool if statuses[player] == "Playing"),
            pool[0],
        )

    if current in pool:
        index = pool.index(current)
    else:
        index = -1 if step > 0 else 0

    write_active_player_state(pool[(index + step) % len(pool)])
    return 0


def fetch_interface_properties(player: str, interface: str) -> dict:
    try:
        return mpris_call(player, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (interface,)))[0]
    except GLib.Error:
        return {}


def fetch_player_properties(player: str) -> dict:
    return fetch_interface_properties(player, "org.mpris.MediaPlayer2.Player")


def fetch_root_properties(player: str) -> dict:
    return fetch_interface_properties(player, "org.mpris.MediaPlayer2")


def _prop_bool(props: dict, name: str) -> bool | None:
    value = props.get(name)
    return value if isinstance(value, bool) else None


def _prop_string(props: dict, name: str) -> str | None:
    value = props.get(name)
    return value if isinstance(value, str) else None


def _metadata_string(props: dict, name: str) -> str:
    metadata = props.get("Metadata")
    value = metadata.get(name) if isinstance(metadata, dict) else None
    return value if isinstance(value, str) else ""


def action_supported(props: dict, action: str) -> bool:
    if action == "play-pause":
        can_play = _prop_bool(props, "CanPlay")
        can_pause = _prop_bool(props, "CanPause")
        return (can_play is not False) or (can_pause is not False)
    capability = CAPABILITY_BY_ACTION.get(action)
    if capability:
        return _prop_bool(props, capability) is not False
    prop = PROPERTY_BY_ACTION.get(action)
    if prop:
        return prop in props
    return True


def run_resolved_action(
    action: str,
    player: str,
    player_props: dict | None = None,
) -> int:
    if player_props is None:
        player_props = fetch_player_properties(player)
    if action == "show-player":
        root_props = fetch_root_properties(player)
        return show_player(
            player,
            desktop_entry=_prop_string(root_props, "DesktopEntry") or "",
            can_raise=_prop_bool(root_props, "CanRaise") is True,
            media_url=_metadata_string(player_props, "xesam:url"),
        )
    if not action_supported(player_props, action):
        return 0

    proc = subprocess.run(
        ["playerctl", "-p", player, *ACTIONS[action]],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return 0 if proc.returncode == 0 else 1


def run_action(action: str, explicit_player: str = "") -> int:
    if action not in ACTIONS:
        raise SystemExit(f"unsupported media action: {action}")

    if action in PLAYER_CYCLE_STEPS:
        return cycle_player(PLAYER_CYCLE_STEPS[action])

    player = resolve_player(explicit_player)
    if not player:
        return 0
    return run_resolved_action(action, player)
