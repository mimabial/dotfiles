from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from game_entry import Game

from pyutils.xdg_base_dirs import xdg_data_home

EXCLUDED_STEAM_NAMES = re.compile(r"\b(proton|steam.*runtime|steamworks|steam client)\b", re.I)


def steamapps_directories() -> list[Path]:
    candidates = [
        xdg_data_home() / "Steam",
        Path.home() / ".steam/steam",
        Path.home() / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
    ]
    roots: list[Path] = []
    for root in candidates:
        if root.is_dir():
            roots.append(root)
        library_file = root / "steamapps/libraryfolders.vdf"
        if not library_file.is_file():
            continue
        try:
            text = library_file.read_text(errors="ignore")
        except OSError:
            continue
        for match in re.finditer(r'"path"\s*"([^"]+)"', text):
            path = Path(match.group(1).replace("\\\\", "\\")).expanduser()
            if path.is_dir():
                roots.append(path)

    seen: set[Path] = set()
    steamapp_dirs: list[Path] = []
    for root in roots:
        steamapps = (root / "steamapps").resolve()
        if steamapps.is_dir() and steamapps not in seen:
            seen.add(steamapps)
            steamapp_dirs.append(steamapps)
    return steamapp_dirs


def manifest_value(text: str, key: str) -> str:
    match = re.search(rf'"{re.escape(key)}"\s*"([^"]*)"', text)
    return match.group(1) if match else ""


def steam_icon(steamapps: Path, appid: str) -> str:
    cache = steamapps.parent / "appcache/librarycache" / appid
    if not cache.is_dir():
        return ""

    phases = [
        ("library_600x900.jpg", "library_capsule.jpg"),
        ("library_hero.jpg", "header.jpg"),
    ]
    dirs = [cache]
    try:
        dirs.extend(sorted(path for path in cache.iterdir() if path.is_dir()))
    except OSError:
        pass

    for names in phases:
        for directory in dirs:
            for name in names:
                candidate = directory / name
                if candidate.is_file():
                    return str(candidate)
    return ""


def steam_games() -> list[Game]:
    games: list[Game] = []
    for steamapps in steamapps_directories():
        for manifest in steamapps.glob("appmanifest_*.acf"):
            try:
                text = manifest.read_text(errors="ignore")
            except OSError:
                continue
            appid = manifest_value(text, "appid")
            name = manifest_value(text, "name")
            if not appid or not name or EXCLUDED_STEAM_NAMES.search(name):
                continue
            games.append(
                Game(
                    key=f"steam:{appid}",
                    backend="steam",
                    name=name,
                    icon=steam_icon(steamapps, appid),
                    argv=["xdg-open", f"steam://rungameid/{appid}"],
                )
            )
    return games

