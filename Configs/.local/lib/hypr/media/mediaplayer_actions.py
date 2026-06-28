#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import tempfile
from pathlib import Path


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
}

PLAYER_CYCLE_STEPS = {
    "cycle-next": 1,
    "cycle-previous": -1,
}

ACTION_LABELS = {
    "play": "Play",
    "pause": "Pause",
    "next": "Next",
    "previous": "Previous",
    "stop": "Stop",
    "shuffle-on": "Shuffle On",
    "shuffle-off": "Shuffle Off",
    "repeat": "Repeat Track",
    "loop": "Repeat Playlist",
    "disable-loop": "Disable Repeat",
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

ROFI_MENU_SCRIPT = r"""
set -euo pipefail

command -v rofi >/dev/null 2>&1 || exit 1

hyprshell_path="$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${hyprshell_path}" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash" || exit 1

if hypr_user_pgrep -x rofi >/dev/null 2>&1; then
  hypr_user_pkill -x rofi
  exit 0
fi

menu_lines="${MEDIA_MENU_LINES:-5}"
[[ "${menu_lines}" =~ ^[0-9]+$ ]] || menu_lines=5
((menu_lines < 1)) && menu_lines=1
((menu_lines > 8)) && menu_lines=8

font_scale=""
font_name=""
font_override=""
r_override=""
_rofi_opacity=""
rofi_position=""
media_window_theme=""

media_width_em="${ROFI_MEDIAPLAYER_MENU_WIDTH_EM:-24}"
media_height_em="${ROFI_MEDIAPLAYER_MENU_HEIGHT_EM:-$((menu_lines * 2 + 7))}"
[[ "${media_width_em}" =~ ^[0-9]+([.][0-9]+)?$ ]] || media_width_em=24
[[ "${media_height_em}" =~ ^[0-9]+([.][0-9]+)?$ ]] || media_height_em=$((menu_lines * 2 + 7))

rofi_prepare_standard_context \
  font_scale font_name font_override r_override _rofi_opacity \
  "${ROFI_MEDIAPLAYER_MENU_SCALE:-${ROFI_MENU_SCALE:-}}" \
  "${ROFI_MEDIAPLAYER_MENU_FONT:-${ROFI_MENU_FONT:-${ROFI_FONT:-}}}" \
  listview same

rofi_picker_compute_window_geometry \
  rofi_position media_window_theme \
  "${font_name}" "${font_scale}" \
  "${media_width_em}" "${media_height_em}" \
  360 220

theme_ref="${ROFI_MEDIAPLAYER_MENU_STYLE:-${ROFI_MEDIAPLAYER_STYLE:-clipboard}}"
placeholder="${MEDIA_MENU_PLACEHOLDER:- Media}"
prompt="${MEDIA_MENU_PROMPT:-Media}"

rofi_args=(
  -dmenu
  -i
  -format i
  -no-custom
  -no-show-icons
  -hover-select
  -me-select-entry ""
  -me-accept-entry MousePrimary
  -p "${prompt}"
  -theme "$(rofi_resolve_theme "${theme_ref}")"
  -theme-str "entry { placeholder: \"${placeholder}\"; } ${rofi_position} ${r_override}"
  -theme-str "${font_override}"
  -theme-str "${media_window_theme}"
)
[[ -n "${_rofi_opacity:-}" ]] && rofi_args+=(-theme-str "${_rofi_opacity}")

input_file="${MEDIA_MENU_INPUT:-}"
[[ -n "${input_file}" && -r "${input_file}" ]] || exit 2
rofi "${rofi_args[@]}" <"${input_file}"
"""


def state_path() -> Path:
    if os.environ.get("HYPR_STATE_HOME"):
        return Path(os.environ["HYPR_STATE_HOME"]) / "mediaplayer.json"
    xdg_state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return xdg_state / "hypr" / "mediaplayer.json"


def write_active_player_state(player_name: str) -> None:
    if not player_name:
        return
    if read_active_player_state() == player_name:
        return
    path = state_path()
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


def clear_active_player_state() -> None:
    try:
        state_path().unlink()
    except FileNotFoundError:
        pass
    except OSError:
        pass


def read_active_player_state() -> str:
    try:
        data = json.loads(state_path().read_text())
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return ""
    return str(data.get("player") or "")


def command_output(args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return proc.returncode, proc.stdout.strip()


def available_players() -> list[str]:
    code, output = command_output(["playerctl", "-l"])
    if code != 0 or not output:
        return []
    players = [line.strip() for line in output.splitlines() if line.strip()]
    configured = [name.strip() for name in os.environ.get("MEDIAPLAYER_PLAYERS", "").split(",") if name.strip()]
    if not configured:
        return players
    return [
        player
        for player in players
        if any(player == name or player.startswith(f"{name}.") for name in configured)
    ]


def player_status(player: str) -> str:
    _, output = command_output(["playerctl", "-p", player, "status"])
    return output


def resolve_player(explicit_player: str = "") -> str:
    players = available_players()
    if not players:
        return ""
    if explicit_player:
        for player in players:
            if player == explicit_player or player.startswith(f"{explicit_player}."):
                return player

    saved = read_active_player_state()
    if saved:
        for player in players:
            if player == saved or player.startswith(f"{saved}."):
                return player

    for player in players:
        if player_status(player) == "Playing":
            return player
    return players[0]


def cycle_player(step: int) -> int:
    players = available_players()
    if not players:
        return 0

    active = [p for p in players if player_status(p) != "Stopped"]
    pool = active if active else players

    selected = read_active_player_state()
    current = ""
    if selected in pool:
        current = selected
    elif selected:
        current = next(
            (player for player in pool if player.startswith(f"{selected}.")),
            "",
        )

    if not current:
        current = resolve_player()

    if current in pool:
        index = pool.index(current)
    else:
        index = -1 if step > 0 else 0

    write_active_player_state(pool[(index + step) % len(pool)])
    return 0


def fetch_player_properties(player: str) -> dict:
    """Return all Player-interface properties via a single busctl GetAll call.
    Output shape: {prop_name: {"type": str, "data": value}, ...}."""
    service = f"org.mpris.MediaPlayer2.{player}"
    proc = subprocess.run(
        [
            "busctl", "--user", "--json=short", "call",
            service,
            "/org/mpris/MediaPlayer2",
            "org.freedesktop.DBus.Properties",
            "GetAll", "s", "org.mpris.MediaPlayer2.Player",
        ],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return {}
    try:
        return json.loads(proc.stdout)["data"][0]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError):
        return {}


def _prop_value(props: dict, name: str):
    entry = props.get(name)
    return entry.get("data") if isinstance(entry, dict) else None


def _prop_bool(props: dict, name: str) -> bool | None:
    value = _prop_value(props, name)
    return value if isinstance(value, bool) else None


def _prop_string(props: dict, name: str) -> str | None:
    value = _prop_value(props, name)
    return value if isinstance(value, str) else None


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
        return _prop_value(props, prop) is not None
    return True


def dynamic_menu_entries(player: str) -> list[tuple[str, str]]:
    props = fetch_player_properties(player)
    status = _prop_string(props, "PlaybackStatus") or player_status(player)
    entries: list[tuple[str, str]] = []

    if action_supported(props, "play-pause"):
        label = ACTION_LABELS["pause"] if status == "Playing" else ACTION_LABELS["play"]
        entries.append((label, "play-pause"))
    if action_supported(props, "next"):
        entries.append((ACTION_LABELS["next"], "next"))
    if action_supported(props, "previous"):
        entries.append((ACTION_LABELS["previous"], "previous"))
    entries.append((ACTION_LABELS["stop"], "stop"))

    if action_supported(props, "shuffle"):
        shuffle = _prop_bool(props, "Shuffle")
        label = ACTION_LABELS["shuffle-off"] if shuffle else ACTION_LABELS["shuffle-on"]
        entries.append((label, "shuffle"))

    loop_status = _prop_string(props, "LoopStatus")
    if loop_status is not None:
        if loop_status != "Track":
            entries.append((ACTION_LABELS["repeat"], "repeat"))
        if loop_status != "Playlist":
            entries.append((ACTION_LABELS["loop"], "loop"))
        if loop_status != "None":
            entries.append((ACTION_LABELS["disable-loop"], "disable-loop"))

    return entries


def rofi_menu_index(labels: list[str], player: str) -> int | None:
    if not labels:
        return None

    env = os.environ.copy()
    env["MEDIA_MENU_LINES"] = str(len(labels))
    env["MEDIA_MENU_PROMPT"] = f"Media: {player.split('.')[0]}"
    env["MEDIA_MENU_PLACEHOLDER"] = " Media"

    input_path = ""
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as input_file:
            input_file.write("\n".join(labels) + "\n")
            input_path = input_file.name
        env["MEDIA_MENU_INPUT"] = input_path
        proc = subprocess.run(
            ["bash", "-lc", ROFI_MENU_SCRIPT],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
    finally:
        if input_path:
            try:
                os.unlink(input_path)
            except OSError:
                pass

    if proc.returncode != 0:
        if proc.returncode not in (1, 130) and proc.stderr.strip():
            print(proc.stderr.strip(), file=sys.stderr)
        return None

    output = proc.stdout.strip()
    if not output:
        return None
    try:
        index = int(output.splitlines()[-1])
    except ValueError:
        return None
    return index if 0 <= index < len(labels) else None


def run_menu(explicit_player: str = "") -> int:
    player = resolve_player(explicit_player)
    if not player:
        return 0
    entries = dynamic_menu_entries(player)
    if not entries:
        return 0

    labels = [label for label, _ in entries]
    selected_index = rofi_menu_index(labels, player)
    if selected_index is None:
        return 0
    return run_action(entries[selected_index][1], player)


def run_action(action: str, explicit_player: str = "") -> int:
    if action not in ACTIONS:
        raise SystemExit(f"unsupported media action: {action}")

    if action in PLAYER_CYCLE_STEPS:
        return cycle_player(PLAYER_CYCLE_STEPS[action])

    player = resolve_player(explicit_player)
    if not player:
        return 0
    if not action_supported(fetch_player_properties(player), action):
        return 0

    proc = subprocess.run(
        ["playerctl", "-p", player, *ACTIONS[action]],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return 0 if proc.returncode == 0 else 1
