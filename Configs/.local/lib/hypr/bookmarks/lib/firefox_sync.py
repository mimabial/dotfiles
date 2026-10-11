from __future__ import annotations

import re
import shutil
import sqlite3
import tempfile
import uuid
from pathlib import Path
from typing import Any

from .records import MAX_IDENTIFIER_CHARS, normalize_bookmark
from .store import read_store_items, write_bookmark_store
from .urls import canonical_http_url


MAX_FIREFOX_PROFILES = 32
LEGACY_FIREFOX_UUID_HEX = re.compile(r"[0-9a-f]{32}\Z")


def read_firefox_bookmarks(source: Path) -> list[dict[str, str]]:
    """Firefox keeps places.sqlite locked while it runs, and recent bookmarks may sit only in its WAL."""
    if not source.is_file():
        raise ValueError("Firefox places database is not a regular file")

    query = """
        SELECT COALESCE(NULLIF(TRIM(b.title), ''), p.url), p.url
        FROM moz_bookmarks AS b
        JOIN moz_places AS p ON b.fk = p.id
        WHERE b.type = 1 AND p.hidden = 0 AND p.url IS NOT NULL
        ORDER BY b.parent, b.position
    """
    with tempfile.TemporaryDirectory(prefix="hypr-bookmarks-") as temp_dir:
        snapshot = Path(temp_dir, "places.sqlite")
        shutil.copy2(source, snapshot)
        wal = Path(f"{source}-wal")
        if wal.is_file():
            shutil.copy2(wal, Path(f"{snapshot}-wal"))
        with sqlite3.connect(snapshot) as database:
            return [
                {"title": title or url, "url": url}
                for title, url in database.execute(query)
            ]


def discover_firefox_databases() -> list[Path]:
    """Not limited to the selected profile."""
    profile_root = Path.home() / ".mozilla/firefox"
    return sorted(
        path for path in profile_root.glob("*/places.sqlite") if path.is_file()
    )[:MAX_FIREFOX_PROFILES]


def is_untagged_legacy_firefox_entry(identifier: str, has_tagged_firefox: bool) -> bool:
    # Old Firefox imports used uuid4 hex IDs; local QML entries use hyphenated IDs.
    return not has_tagged_firefox and LEGACY_FIREFOX_UUID_HEX.fullmatch(identifier) is not None


def firefox_items_by_url(source_items: list[dict[str, str]]) -> tuple[dict[str, dict[str, Any]], int, int]:
    firefox_items: dict[str, dict[str, Any]] = {}
    rejected = duplicates = 0
    for raw_item in source_items:
        item = normalize_bookmark(raw_item, favicon_policy="none", preserve_usage_history=False)
        if item is None:
            rejected += 1
            continue
        key = canonical_http_url(item["url"])
        if key in firefox_items:
            duplicates += 1
            if not firefox_items[key]["title"] and item["title"]:
                firefox_items[key]["title"] = item["title"]
            continue
        item["source"] = "firefox"
        firefox_items[key] = item
    return firefox_items, rejected, duplicates


def merge_firefox_items(
    existing_items: list[dict[str, Any]],
    firefox_items: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    has_tagged_firefox = any(
        isinstance(item, dict) and item.get("source") == "firefox"
        for item in existing_items
    )
    merged: list[dict[str, Any]] = []
    known: set[str] = set()
    counts = {"new": 0, "updated": 0, "removed": 0, "tagged": 0}

    for raw_item in existing_items:
        item = normalize_bookmark(raw_item, favicon_policy="stored")
        identifier = (
            str(raw_item.get("id") or "").strip()
            if isinstance(raw_item, dict)
            else ""
        )
        if item is None or not identifier or len(identifier) > MAX_IDENTIFIER_CHARS:
            raise ValueError("Bookmarks store contains an invalid entry")
        item["id"] = identifier
        key = canonical_http_url(item["url"])
        if key in known:
            raise ValueError("Bookmarks store contains duplicate URLs")

        firefox_owned = item["source"] == "firefox" or is_untagged_legacy_firefox_entry(
            identifier, has_tagged_firefox
        )
        incoming = firefox_items.get(key)
        if firefox_owned and incoming is None:
            counts["removed"] += 1
            continue
        if firefox_owned:
            if item["title"] != incoming["title"] or item["url"] != incoming["url"]:
                counts["updated"] += 1
            if item["source"] != "firefox":
                counts["tagged"] += 1
            item["title"] = incoming["title"]
            item["url"] = incoming["url"]
            item["source"] = "firefox"

        known.add(key)
        merged.append(item)

    for key, incoming in firefox_items.items():
        if key in known:
            continue
        incoming["id"] = uuid.uuid4().hex
        merged.append(incoming)
        known.add(key)
        counts["new"] += 1
    return merged, counts


def sync_firefox(
    store_path: str,
    sources: list[Path],
) -> dict[str, Any]:
    if not sources:
        raise ValueError("No Firefox bookmark database was found")

    source_items: list[dict[str, str]] = []
    for source in sources:
        source_items.extend(read_firefox_bookmarks(source))

    firefox_items, rejected, duplicates = firefox_items_by_url(source_items)
    merged, counts = merge_firefox_items(read_store_items(store_path), firefox_items)
    changed = sum(counts.values())
    backup_path = write_bookmark_store(store_path, merged) if changed else ""

    return {
        "ok": True,
        "stats": {
            "found": len(source_items),
            "current": len(firefox_items),
            **counts,
            "duplicates": duplicates,
            "rejected": rejected,
            "changed": changed,
            "total": len(merged),
        },
        "backup": backup_path,
    }


def import_firefox(source_arg: str, store_path: str) -> dict[str, Any]:
    return sync_firefox(store_path, [Path(source_arg)])


def sync_discovered_firefox(store_path: str) -> dict[str, Any]:
    return sync_firefox(store_path, discover_firefox_databases())
