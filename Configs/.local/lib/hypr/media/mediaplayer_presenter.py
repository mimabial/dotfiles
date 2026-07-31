#!/usr/bin/env python3
"""Focus the selected MPRIS player's window or create its frontend."""

from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path


PLAYER_ALIASES = {
    "elisa": ("elisa", "org.kde.elisa"),
    "mpd": ("org.tui.Rmpc",),
    "mpv": ("mpv",),
    "spotify": ("spotify",),
    "vlc": ("vlc",),
}


def command(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )


def player_base(player: str) -> str:
    if player.startswith("fftab_"):
        return "fftab"
    return player.split(".", 1)[0].lower()


def window_aliases(player: str, desktop_entry: str = "") -> tuple[str, ...]:
    base = player_base(player)
    aliases = ["firefox"] if base == "fftab" else list(
        PLAYER_ALIASES.get(base, (base,))
    )
    desktop_entry = desktop_entry.removesuffix(".desktop").strip()
    if desktop_entry:
        aliases.append(desktop_entry)
    return tuple(dict.fromkeys(alias for alias in aliases if alias))


def hypr_clients() -> list[dict]:
    proc = command(["hyprctl", "clients", "-j"])
    if proc.returncode != 0 or not proc.stdout.strip():
        return []
    try:
        clients = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []
    return clients if isinstance(clients, list) else []


def matching_window(player: str, desktop_entry: str = "") -> dict | None:
    aliases = {alias.casefold() for alias in window_aliases(player, desktop_entry)}
    matches = []
    for client in hypr_clients():
        classes = {
            str(client.get("class") or "").casefold(),
            str(client.get("initialClass") or "").casefold(),
        }
        if aliases & classes:
            matches.append(client)
    if not matches:
        return None
    return next((client for client in matches if client.get("focusHistoryID") == 0), matches[0])


def focus_window(address: str) -> bool:
    if not address:
        return False
    selector = json.dumps(f"address:{address}")
    proc = command(
        ["hyprctl", "dispatch", f"hl.dsp.focus({{window={selector}}})"]
    )
    return proc.returncode == 0


def focus_empty_workspace() -> bool:
    proc = command(
        ["hyprctl", "dispatch", 'hl.dsp.focus({workspace="empty"})']
    )
    return proc.returncode == 0


def raise_mpris_player(player: str) -> bool:
    service = f"org.mpris.MediaPlayer2.{player}"
    proc = command(
        [
            "busctl",
            "--user",
            "call",
            service,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2",
            "Raise",
        ]
    )
    return proc.returncode == 0


def wait_for_window(
    player: str,
    desktop_entry: str,
    attempts: int = 30,
) -> dict | None:
    for _attempt in range(attempts):
        window = matching_window(player, desktop_entry)
        if window is not None:
            return window
        time.sleep(0.1)
    return None


def launch_spec(
    player: str,
    desktop_entry: str,
    media_url: str,
) -> tuple[str, list[str]] | None:
    base = player_base(player)
    hyprshell = shutil.which("hyprshell") or str(Path.home() / ".local/bin/hyprshell")
    if base == "mpd":
        return (
            "class:org.tui.Rmpc",
            [
                hyprshell,
                "launch/tui.sh",
                "--app-id",
                "org.tui.Rmpc",
                "--title",
                "Rmpc",
                "--",
                str(Path.home() / ".config/rmpc/lib/launch"),
            ],
        )
    if base == "elisa":
        return "class:elisa", ["elisa"]
    if base == "fftab":
        launch = ["firefox"]
        if media_url:
            launch.append(media_url)
        return "class:firefox", launch

    aliases = window_aliases(player, desktop_entry)
    pattern = f"class:{aliases[0]}" if aliases else player
    if desktop_entry and shutil.which("gtk-launch"):
        return pattern, ["gtk-launch", desktop_entry.removesuffix(".desktop")]
    executable = shutil.which(base)
    if executable:
        launch = [executable]
        if media_url and base in ("mpv", "vlc"):
            launch.append(media_url)
        return pattern, launch
    return None


def launch_on_empty_workspace(
    player: str,
    desktop_entry: str,
    media_url: str,
) -> bool:
    spec = launch_spec(player, desktop_entry, media_url)
    if spec is None:
        return False
    pattern, launch = spec
    hyprshell = shutil.which("hyprshell") or str(Path.home() / ".local/bin/hyprshell")
    proc = command(
        [
            hyprshell,
            "launch/summon.sh",
            "--empty-workspace-if-occupied",
            pattern,
            "--",
            *launch,
        ]
    )
    return proc.returncode == 0


def show_player(
    player: str,
    desktop_entry: str = "",
    can_raise: bool = False,
    media_url: str = "",
) -> int:
    is_firefox_tab = player_base(player) == "fftab"
    if is_firefox_tab:
        raise_mpris_player(player)
        time.sleep(0.15)

    window = matching_window(player, desktop_entry)
    if window is not None:
        return 0 if focus_window(str(window.get("address") or "")) else 1

    if not focus_empty_workspace():
        return 1
    if can_raise and raise_mpris_player(player):
        window = wait_for_window(player, desktop_entry)
        if window is not None:
            return 0 if focus_window(str(window.get("address") or "")) else 1
    return 0 if launch_on_empty_workspace(player, desktop_entry, media_url) else 1
