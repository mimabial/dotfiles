"""Persistent cache for lyrics misses and temporary provider cooldowns."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import threading
import time
from pathlib import Path

MISS_TTL = 60 * 60


def cache_home() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))


def miss_cache_key(
    artist: str,
    title: str,
    album: str,
    expected_duration: float | None,
    prefer_synced: bool,
    synced_only: bool = False,
) -> str:
    payload = {
        "artist": artist.casefold().strip(),
        "title": title.casefold().strip(),
        "album": album.casefold().strip(),
        "duration": round(expected_duration or 0),
        "prefer_synced": prefer_synced,
        "synced_only": synced_only,
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


class LyricsMissCache:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self.connection = sqlite3.connect(path, timeout=5, check_same_thread=False)
        os.chmod(path, 0o600)
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS misses (
                cache_key TEXT PRIMARY KEY,
                expires_at REAL NOT NULL
            )
            """
        )
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS provider_cooldowns (
                provider TEXT PRIMARY KEY,
                expires_at REAL NOT NULL
            )
            """
        )
        self.connection.execute(
            "DELETE FROM misses WHERE expires_at <= ?",
            (time.time(),),
        )
        self.connection.execute(
            "DELETE FROM provider_cooldowns WHERE expires_at <= ?",
            (time.time(),),
        )
        self.connection.commit()

    def contains(self, cache_key: str) -> bool:
        with self._lock:
            row = self.connection.execute(
                "SELECT expires_at FROM misses WHERE cache_key = ?",
                (cache_key,),
            ).fetchone()
            if row is None:
                return False
            if row[0] > time.time():
                return True
            self.connection.execute(
                "DELETE FROM misses WHERE cache_key = ?",
                (cache_key,),
            )
            self.connection.commit()
            return False

    def put(self, cache_key: str, ttl: int = MISS_TTL) -> None:
        with self._lock:
            self.connection.execute(
                """
                INSERT INTO misses(cache_key, expires_at)
                VALUES (?, ?)
                ON CONFLICT(cache_key) DO UPDATE SET expires_at = excluded.expires_at
                """,
                (cache_key, time.time() + ttl),
            )
            self.connection.commit()

    def discard(self, cache_key: str) -> None:
        with self._lock:
            self.connection.execute(
                "DELETE FROM misses WHERE cache_key = ?",
                (cache_key,),
            )
            self.connection.commit()

    def cooldown_until(self, provider: str) -> float | None:
        with self._lock:
            row = self.connection.execute(
                "SELECT expires_at FROM provider_cooldowns WHERE provider = ?",
                (provider,),
            ).fetchone()
            if row is None:
                return None

            expires_at = float(row[0])
            if expires_at > time.time():
                return expires_at

            self.connection.execute(
                "DELETE FROM provider_cooldowns WHERE provider = ?",
                (provider,),
            )
            self.connection.commit()
            return None

    def put_cooldown(self, provider: str, ttl: int) -> float:
        expires_at = time.time() + ttl
        with self._lock:
            self.connection.execute(
                """
                INSERT INTO provider_cooldowns(provider, expires_at)
                VALUES (?, ?)
                ON CONFLICT(provider) DO UPDATE
                SET expires_at = excluded.expires_at
                """,
                (provider, expires_at),
            )
            self.connection.commit()
        return expires_at

    def close(self) -> None:
        with self._lock:
            self.connection.close()


_CACHE: LyricsMissCache | None = None
_CACHE_UNAVAILABLE = False


def lyrics_miss_cache() -> LyricsMissCache | None:
    global _CACHE, _CACHE_UNAVAILABLE
    if _CACHE is not None:
        return _CACHE
    if _CACHE_UNAVAILABLE:
        return None
    try:
        _CACHE = LyricsMissCache(cache_home() / "hypr" / "lyrics.sqlite3")
    except (OSError, sqlite3.Error):
        _CACHE_UNAVAILABLE = True
    return _CACHE
