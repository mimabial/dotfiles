from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils.xdg_base_dirs import xdg_cache_home, xdg_data_home
from game_entry import Game

LUTRIS_DB_NAMES = ("pga.db", "lutris.db", "db.sqlite")
LUTRIS_FLATPAK_DATA = Path.home() / ".var/app/net.lutris.Lutris/data/lutris"
LUTRIS_SNAP_DB = Path.home() / "snap/lutris/current/.local/share/lutris/pga.db"


def lutris_data_dirs() -> list[Path]:
    return [xdg_data_home() / "lutris", LUTRIS_FLATPAK_DATA]


def lutris_db_paths() -> list[Path]:
    candidates = [root / name for root in lutris_data_dirs() for name in LUTRIS_DB_NAMES]
    candidates.append(LUTRIS_SNAP_DB)
    found = [path for path in candidates if path.is_file()]
    if found:
        return sorted(set(found), key=lambda path: path.stat().st_mtime, reverse=True)

    for root in lutris_data_dirs():
        if root.is_dir():
            found.extend(path for path in root.rglob("*.db") if path.is_file())
    return sorted(set(found), key=lambda path: path.stat().st_mtime, reverse=True)


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
    cover_dirs = [root / "coverart" for root in lutris_data_dirs()]
    cover_dirs.append(xdg_cache_home() / "lutris/coverart")
    for directory in cover_dirs:
        for suffix in (".jpg", ".png"):
            candidate = directory / f"{slug}{suffix}"
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

