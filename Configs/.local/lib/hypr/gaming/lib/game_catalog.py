#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import shutil
import subprocess
import sys
from dataclasses import asdict

from game_entry import Game
from steam_catalog import steam_games
from lutris_catalog import lutris_games


def collect_game_catalog(backend: str) -> list[Game]:
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


def game_display_name(game: Game, duplicates: set[str]) -> str:
    name = html.escape(game.name, quote=False)
    if game.name.casefold() not in duplicates:
        return name
    return f"{name} <span foreground='gray'>({game.backend})</span>"


def print_rofi_entries(games: list[Game]) -> None:
    counts: dict[str, int] = {}
    for game in games:
        key = game.name.casefold()
        counts[key] = counts.get(key, 0) + 1
    duplicates = {name for name, count in counts.items() if count > 1}

    for game in games:
        suffix = f"\0icon\x1f{game.icon}" if game.icon else ""
        print(f"{game_display_name(game, duplicates)}\t{game.key}{suffix}")


def launch_catalog_game(games: list[Game], key: str) -> None:
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

    games = collect_game_catalog(args.backend)
    if args.launch:
        launch_catalog_game(games, args.launch)
    elif args.json:
        print(json.dumps([asdict(game) for game in games], indent=2))
    else:
        print_rofi_entries(games)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
