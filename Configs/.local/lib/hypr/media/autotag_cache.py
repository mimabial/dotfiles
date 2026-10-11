from __future__ import annotations

import json
import os
import sqlite3
import time
from pathlib import Path


# Rescans should not repeat an unchanged lookup. Successful metadata changes
# slowly; misses and temporary provider blocks are retried after one hour.
CACHE_VERSION = 1


CACHE_SUCCESS_TTL = 99 * 24 * 60 * 60


CACHE_MISS_TTL = 60 * 60


CACHE_COMMIT_BATCH = 64


class ResolutionCache:
    """Catalog misses are cached too, and expire."""

    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path, timeout=5)
        os.chmod(path, 0o600)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=NORMAL")
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS resolutions (
                cache_key TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                expires_at REAL NOT NULL
            )
            """
        )
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS state (
                state_key TEXT PRIMARY KEY,
                expires_at REAL NOT NULL
            )
            """
        )
        self.connection.execute(
            "DELETE FROM resolutions WHERE expires_at <= ?",
            (time.time(),),
        )
        self.connection.execute(
            "DELETE FROM state WHERE expires_at <= ?",
            (time.time(),),
        )
        self.connection.commit()
        self._pending_writes = 0
        self.hits = 0
        self.misses = 0

    def _mark_dirty(self) -> None:
        self._pending_writes += 1
        if self._pending_writes >= CACHE_COMMIT_BATCH:
            self.flush()

    def flush(self) -> None:
        if not self._pending_writes:
            return
        self.connection.commit()
        self._pending_writes = 0

    def get(self, cache_key: str) -> dict | None:
        row = self.connection.execute(
            "SELECT payload, expires_at FROM resolutions WHERE cache_key = ?",
            (cache_key,),
        ).fetchone()
        if row is None:
            self.misses += 1
            return None
        if row[1] <= time.time():
            self.connection.execute(
                "DELETE FROM resolutions WHERE cache_key = ?",
                (cache_key,),
            )
            self._mark_dirty()
            self.misses += 1
            return None
        try:
            payload = json.loads(row[0])
        except (TypeError, json.JSONDecodeError):
            self.connection.execute(
                "DELETE FROM resolutions WHERE cache_key = ?",
                (cache_key,),
            )
            self._mark_dirty()
            self.misses += 1
            return None
        self.hits += 1
        return payload

    def put(self, cache_key: str, payload: dict, ttl: int) -> None:
        self.connection.execute(
            """
            INSERT INTO resolutions(cache_key, payload, expires_at)
            VALUES (?, ?, ?)
            ON CONFLICT(cache_key) DO UPDATE SET
                payload = excluded.payload,
                expires_at = excluded.expires_at
            """,
            (cache_key, json.dumps(payload, ensure_ascii=False), time.time() + ttl),
        )
        self._mark_dirty()

    def state_active(self, state_key: str) -> bool:
        row = self.connection.execute(
            "SELECT expires_at FROM state WHERE state_key = ?",
            (state_key,),
        ).fetchone()
        return row is not None and row[0] > time.time()

    def put_state(self, state_key: str, ttl: int) -> None:
        self.connection.execute(
            """
            INSERT INTO state(state_key, expires_at)
            VALUES (?, ?)
            ON CONFLICT(state_key) DO UPDATE SET expires_at = excluded.expires_at
            """,
            (state_key, time.time() + ttl),
        )
        # Provider cooldowns are rare and must survive an interrupted run.
        self.connection.commit()
        self._pending_writes = 0

    def close(self) -> None:
        self.flush()
        self.connection.close()

