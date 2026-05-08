#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class Game:
    key: str
    backend: str
    name: str
    icon: str
    argv: list[str]


EXCLUDED_STEAM_NAMES = re.compile(r"\b(proton|steam.*runtime|steamworks|steam client)\b", re.I)


def xdg_data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))


def steam_roots() -> list[Path]:
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
    out: list[Path] = []
    for root in roots:
        steamapps = (root / "steamapps").resolve()
        if steamapps.is_dir() and steamapps not in seen:
            seen.add(steamapps)
            out.append(steamapps)
    return out


def acf_value(text: str, key: str) -> str:
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
    for steamapps in steam_roots():
        for manifest in steamapps.glob("appmanifest_*.acf"):
            try:
                text = manifest.read_text(errors="ignore")
            except OSError:
                continue
            appid = acf_value(text, "appid")
            name = acf_value(text, "name")
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


def lutris_db_paths() -> list[Path]:
    data_home = xdg_data_home()
    candidates = [
        data_home / "lutris/pga.db",
        data_home / "lutris/lutris.db",
        data_home / "lutris/db.sqlite",
        Path.home() / ".var/app/net.lutris.Lutris/data/lutris/pga.db",
        Path.home() / ".var/app/net.lutris.Lutris/data/lutris/lutris.db",
        Path.home() / ".var/app/net.lutris.Lutris/data/lutris/db.sqlite",
        Path.home() / "snap/lutris/current/.local/share/lutris/pga.db",
    ]
    found = [path for path in candidates if path.is_file()]
    if found:
        return sorted(set(found), key=lambda p: p.stat().st_mtime, reverse=True)

    scan_roots = [data_home / "lutris", Path.home() / ".var/app/net.lutris.Lutris/data/lutris"]
    for root in scan_roots:
        if root.is_dir():
            found.extend(path for path in root.rglob("*.db") if path.is_file())
    return sorted(set(found), key=lambda p: p.stat().st_mtime, reverse=True)


def table_columns(cursor: sqlite3.Cursor, table: str) -> set[str]:
    try:
        cursor.execute(f"PRAGMA table_info({table})")
    except sqlite3.Error:
        return set()
    return {str(row[1]) for row in cursor.fetchall()}


def lutris_rows(db_path: Path) -> list[dict]:
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    try:
        cursor = conn.cursor()
        for table in ("games", "installed_game", "game"):
            cols = table_columns(cursor, table)
            if not {"name", "slug"} <= cols:
                continue
            selected = [col for col in ("id", "name", "slug", "runner", "icon", "prefix", "path") if col in cols]
            cursor.execute(f"SELECT {', '.join(selected)} FROM {table}")
            rows = [dict(row) for row in cursor.fetchall()]
            if rows:
                return rows
    finally:
        conn.close()
    return []


def lutris_icon(slug: str) -> str:
    if not slug:
        return ""
    candidates = [
        Path.home() / ".local/share/lutris/coverart" / f"{slug}.jpg",
        Path.home() / ".local/share/lutris/coverart" / f"{slug}.png",
        Path.home() / ".var/app/net.lutris.Lutris/data/lutris/coverart" / f"{slug}.jpg",
        Path.home() / ".var/app/net.lutris.Lutris/data/lutris/coverart" / f"{slug}.png",
        Path.home() / ".cache/lutris/coverart" / f"{slug}.jpg",
        Path.home() / ".cache/lutris/coverart" / f"{slug}.png",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return ""


def lutris_games() -> list[Game]:
    for db_path in lutris_db_paths():
        try:
            rows = lutris_rows(db_path)
        except sqlite3.Error as exc:
            print(f"lutris: {db_path}: {exc}", file=sys.stderr)
            continue
        games: list[Game] = []
        for row in rows:
            name = str(row.get("name") or "").strip()
            slug = str(row.get("slug") or "").strip()
            if not name or not slug:
                continue
            games.append(
                Game(
                    key=f"lutris:{slug}",
                    backend="lutris",
                    name=name,
                    icon=lutris_icon(slug),
                    argv=["xdg-open", f"lutris:rungame/{slug}"],
                )
            )
        return games
    return []


def catalog(backend: str) -> list[Game]:
    games: list[Game] = []
    if backend in ("all", "steam"):
        games.extend(steam_games())
    if backend in ("all", "lutris"):
        games.extend(lutris_games())

    seen: set[str] = set()
    unique: list[Game] = []
    for game in sorted(games, key=lambda g: (g.name.casefold(), g.backend)):
        if game.key in seen:
            continue
        seen.add(game.key)
        unique.append(game)
    return unique


def display_name(game: Game, duplicates: set[str]) -> str:
    if game.name.casefold() not in duplicates:
        return game.name
    return f"{game.name} <span foreground='gray'>({game.backend})</span>"


def print_rofi(games: list[Game]) -> None:
    counts: dict[str, int] = {}
    for game in games:
        key = game.name.casefold()
        counts[key] = counts.get(key, 0) + 1
    duplicates = {name for name, count in counts.items() if count > 1}

    for game in games:
        suffix = f"\0icon\x1f{game.icon}" if game.icon else ""
        print(f"{display_name(game, duplicates)}\t{game.key}{suffix}")


def launch(games: list[Game], key: str) -> None:
    game = next((candidate for candidate in games if candidate.key == key), None)
    if game is None:
        raise SystemExit(f"game not found: {key}")
    if not shutil.which(game.argv[0]):
        raise SystemExit(f"missing launcher: {game.argv[0]}")
    subprocess.Popen(game.argv, start_new_session=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Steam/Lutris game catalog.")
    parser.add_argument("--backend", "-b", choices=("all", "steam", "lutris"), default="all")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--rofi", action="store_true")
    parser.add_argument("--launch")
    args = parser.parse_args()

    games = catalog(args.backend)
    if args.launch:
        launch(games, args.launch)
    elif args.json:
        print(json.dumps([asdict(game) for game in games], indent=2))
    else:
        print_rofi(games)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
