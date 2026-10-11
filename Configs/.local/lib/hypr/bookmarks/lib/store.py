from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from .bounded_io import atomic_write, existing_regular_mode, read_limited_bytes, read_limited_text
from .records import MAX_IDENTIFIER_CHARS, normalize_bookmark


STORE_VERSION = 3
MAX_STORE_BYTES = 64 * 1024 * 1024
MAX_BOOKMARKS = 50_000
BACKUP_LIMIT = 10


def read_store_items(path: str) -> list[dict[str, Any]]:
    store_path = Path(path)
    try:
        raw = read_limited_text(
            store_path,
            MAX_STORE_BYTES,
            "Bookmarks store",
            follow_symlinks=False,
        )
    except FileNotFoundError:
        return []
    data = json.loads(raw)
    if isinstance(data, list):
        source = data
    elif isinstance(data, dict) and isinstance(data.get("bookmarks"), list):
        if int(data.get("version") or 0) > STORE_VERSION:
            raise ValueError("bookmarks.json uses a newer data format")
        source = data["bookmarks"]
    else:
        raise ValueError("bookmarks.json must contain a bookmarks array")
    if len(source) > MAX_BOOKMARKS:
        raise ValueError(f"Bookmarks store contains more than {MAX_BOOKMARKS} entries")
    return source


def load_store_document(path: str) -> dict[str, Any]:
    source = read_store_items(path)
    bookmarks: list[dict[str, Any]] = []
    invalid = 0
    for raw_item in source:
        item = normalize_bookmark(raw_item, favicon_policy="stored")
        identifier = (
            str(raw_item.get("id") or "").strip()
            if isinstance(raw_item, dict)
            else ""
        )
        if item is None or not identifier or len(identifier) > MAX_IDENTIFIER_CHARS:
            invalid += 1
            continue
        item["id"] = identifier
        bookmarks.append(item)
    return {
        "ok": True,
        "data": {"version": STORE_VERSION, "bookmarks": bookmarks},
        "invalid": invalid,
    }


def save_store_from_stdin(path: str) -> dict[str, Any]:
    raw = sys.stdin.buffer.read(MAX_STORE_BYTES + 1)
    if len(raw) > MAX_STORE_BYTES:
        raise ValueError("Bookmarks store is too large")
    text = raw.decode("utf-8")
    data = json.loads(text)
    if not isinstance(data, dict) or not isinstance(data.get("bookmarks"), list):
        raise ValueError("bookmarks.json must contain a bookmarks array")
    if len(data["bookmarks"]) > MAX_BOOKMARKS:
        raise ValueError(f"Bookmarks store contains more than {MAX_BOOKMARKS} entries")

    destination = Path(path)
    mode = existing_regular_mode(destination, "Bookmarks store", 0o600)
    atomic_write(destination, text, mode)
    return {"ok": True}


def write_bookmark_store(store_path: str, bookmarks: list[dict[str, Any]]) -> str:
    backup = create_and_prune_store_backups(store_path)
    destination = Path(store_path)
    mode = existing_regular_mode(destination, "Bookmarks store", 0o600)
    document = json.dumps(
        {"version": STORE_VERSION, "bookmarks": bookmarks},
        ensure_ascii=False,
        indent=2,
    ) + "\n"
    atomic_write(destination, document, mode)
    return str(backup.get("backup", ""))


def create_and_prune_store_backups(store_path: str, keep: int = BACKUP_LIMIT) -> dict[str, Any]:
    source = Path(store_path)
    try:
        contents = read_limited_bytes(
            source,
            MAX_STORE_BYTES,
            "Bookmarks store",
            follow_symlinks=False,
        )
    except FileNotFoundError:
        return {"ok": True, "skipped": True, "backup": "", "pruned": 0}

    keep = max(1, int(keep))
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    destination = Path(str(source) + ".backup-" + stamp)
    counter = 0
    while destination.exists():
        counter += 1
        destination = Path(str(source) + f".backup-{stamp}-{counter}")

    atomic_write(destination, contents, 0o600)

    pattern = source.name + ".backup-*"
    backups = sorted(
        (path for path in source.parent.glob(pattern) if path.is_file()),
        key=lambda path: (path.stat().st_mtime_ns, path.name),
        reverse=True,
    )
    pruned = 0
    for old_backup in backups[keep:]:
        old_backup.unlink()
        pruned += 1
    return {
        "ok": True,
        "skipped": False,
        "backup": str(destination),
        "pruned": pruned,
    }
