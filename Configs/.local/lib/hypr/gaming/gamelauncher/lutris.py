#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
from pathlib import Path

DEFAULT_LUTRIS_DBS = [
    Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "lutris" / "pga.db",
    Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "lutris" / "lutris.db",
    Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "lutris" / "db.sqlite",
    Path.home() / ".var" / "app" / "net.lutris.Lutris" / "data" / "lutris" / "pga.db",
    Path.home() / ".var" / "app" / "net.lutris.Lutris" / "data" / "lutris" / "lutris.db",
    Path.home() / ".var" / "app" / "net.lutris.Lutris" / "data" / "lutris" / "db.sqlite",
    Path.home() / "snap" / "lutris" / "current" / ".local" / "share" / "lutris" / "pga.db",
]


def find_lutris_db() -> Path | None:
    existing = [path for path in DEFAULT_LUTRIS_DBS if path.exists() and path.is_file()]
    if not existing:
        return None
    return sorted(existing, key=lambda item: item.stat().st_mtime, reverse=True)[0]


def query_games(database_path: Path) -> list[dict]:
    conn = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    games: list[dict] = []

    queries = [
        "SELECT id, name, slug, runner, prefix, IFNULL(icon, '') AS icon FROM games",
        "SELECT id, name, slug, runner, path, IFNULL(icon, '') AS icon FROM games",
    ]

    for query in queries:
        try:
            cursor.execute(query)
            rows = cursor.fetchall()
            if not rows:
                continue
            for row in rows:
                games.append(
                    {
                        "id": row["id"],
                        "name": row["name"],
                        "slug": row["slug"],
                        "backend": "lutris",
                        "path": row["prefix"] if "prefix" in row.keys() else (row["path"] if "path" in row.keys() else ""),
                        "icon": row["icon"] or "",
                    }
                )
            conn.close()
            return games
        except sqlite3.Error:
            continue

    conn.close()
    return games


def lutris_cover_path(slug: str) -> str:
    candidates = [
        Path.home() / ".local" / "share" / "lutris" / "coverart" / f"{slug}.jpg",
        Path.home() / ".local" / "share" / "lutris" / "coverart" / f"{slug}.png",
        Path.home() / ".var" / "app" / "net.lutris.Lutris" / "data" / "lutris" / "coverart" / f"{slug}.jpg",
        Path.home() / ".var" / "app" / "net.lutris.Lutris" / "data" / "lutris" / "coverart" / f"{slug}.png",
        Path.home() / ".cache" / "lutris" / "coverart" / f"{slug}.jpg",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return ""


def list_games() -> list[dict]:
    database_path = find_lutris_db()
    if database_path is None:
        return []

    entries = []
    for game in query_games(database_path):
        cover = lutris_cover_path(game.get("slug") or "")
        run_command = f'xdg-open "lutris:rungame/{game["slug"]}"'
        entry = {
            "id": game["id"],
            "name": game["name"],
            "slug": game["slug"],
            "backend": "lutris",
            "path": game.get("path") or "",
            "cover": cover,
            "icon": game.get("icon") or "",
            "run_command": run_command,
        }
        entries.append(entry)

    return sorted(entries, key=lambda item: item["name"].lower())


def emit_rofi(entries: list[dict]) -> None:
    for entry in entries:
        row = f"{entry['name']}\t{entry['run_command']}"
        icon_path = entry.get("cover") or entry.get("icon")
        if icon_path:
            row += f"\t\x00icon\x1f{icon_path}"
        print(row)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--detect", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--rofi-string", action="store_true")
    args = parser.parse_args()

    db_path = find_lutris_db()
    if args.detect:
        print(json.dumps([str(db_path)] if db_path else [], indent=2))
        return 0

    entries = list_games()
    if args.json:
        print(json.dumps(entries, indent=2))
        return 0
    if args.rofi_string:
        emit_rofi(entries)
        return 0

    print(json.dumps(entries, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
