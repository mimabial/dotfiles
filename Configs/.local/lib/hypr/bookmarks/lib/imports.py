from __future__ import annotations

import html
import json
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, NamedTuple
from urllib.parse import unquote, urlsplit

from .bounded_io import read_limited_text
from .records import MAX_TITLE_CHARS, normalize_bookmark, normalize_tags
from .store import MAX_BOOKMARKS, read_store_items
from .urls import canonical_http_url


HTML_SNIFF_CHARS = 1000
NETSCAPE_DOCTYPE = "<!DOCTYPE NETSCAPE-Bookmark-file"
MAX_IMPORT_BYTES = 50_000_000
MAX_IMPORT_ICONS = 512


class BookmarkHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.items: list[dict[str, Any]] = []
        self._link_attributes: dict[str, str] | None = None
        self._link_title_parts: list[str] = []
        self._title_length = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == "a":
            self._link_attributes = {str(k).upper(): str(v or "") for k, v in attrs}
            self._link_title_parts = []
            self._title_length = 0

    def handle_data(self, data: str) -> None:
        if self._link_attributes is not None:
            remaining = MAX_TITLE_CHARS - self._title_length
            if remaining > 0:
                part = data[:remaining]
                self._link_title_parts.append(part)
                self._title_length += len(part)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() != "a" or self._link_attributes is None:
            return
        if len(self.items) >= MAX_BOOKMARKS:
            raise ValueError(f"Bookmark file contains more than {MAX_BOOKMARKS} entries")
        self.items.append({
            "title": html.unescape("".join(self._link_title_parts)).strip(),
            "url": html.unescape(self._link_attributes.get("HREF", "")).strip(),
            "tags": normalize_tags(self._link_attributes.get("TAGS", "")),
            "keyword": self._link_attributes.get("SHORTCUTURL", "").strip(),
            "iconSource": self._link_attributes.get("ICON", "").strip(),
        })
        self._link_attributes = None
        self._link_title_parts = []


class ImportSource(NamedTuple):
    raw_bookmarks: list[Any]
    format_name: str
    icon_source_field: str
    preserve_usage_history: bool


def read_import_source(source_arg: str) -> ImportSource:
    if source_arg.startswith("file:"):
        source_arg = unquote(urlsplit(source_arg).path)
    source_path = Path(source_arg)
    raw = read_limited_text(source_path, MAX_IMPORT_BYTES, "Bookmark file")

    if source_path.suffix.lower() in (".html", ".htm") or NETSCAPE_DOCTYPE in raw[:HTML_SNIFF_CHARS]:
        parser = BookmarkHTMLParser()
        parser.feed(raw)
        return ImportSource(parser.items, "HTML", "iconSource", False)

    data = json.loads(raw)
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict):
        items = data.get("bookmarks", [])
    else:
        raise ValueError("JSON must be an array or object containing bookmarks")
    if not isinstance(items, list):
        raise ValueError("JSON must contain a bookmarks array")
    return ImportSource(items, "JSON", "favicon", True)


def merge_duplicate_import(current: dict[str, Any], item: dict[str, Any]) -> None:
    if not current["title"] and item["title"]:
        current["title"] = item["title"]
    current["tags"] = normalize_tags(current["tags"] + item["tags"])
    if not current["keyword"] and item["keyword"]:
        current["keyword"] = item["keyword"]
    if not current["favicon"] and item["favicon"]:
        current["favicon"] = item["favicon"]
    if item["usageScore"] > current["usageScore"]:
        current["usageScore"] = item["usageScore"]
        current["lastOpenedAt"] = item["lastOpenedAt"]


def prepare_bookmark_import(source_arg: str, store_path: str) -> dict[str, Any]:
    source = read_import_source(source_arg)
    if len(source.raw_bookmarks) > MAX_BOOKMARKS:
        raise ValueError(f"Bookmark file contains more than {MAX_BOOKMARKS} entries")

    existing = {canonical_http_url(item.get("url")): item for item in read_store_items(store_path)}
    result: list[dict[str, Any]] = []
    positions: dict[str, int] = {}
    rejected = 0
    duplicates_in_file = 0
    duplicates_existing = 0
    processed_icons = 0

    for raw_item in source.raw_bookmarks:
        should_process_icon = (
            processed_icons < MAX_IMPORT_ICONS
            and isinstance(raw_item, dict)
            and bool(raw_item.get(source.icon_source_field))
        )
        if should_process_icon:
            processed_icons += 1
        item = normalize_bookmark(
            raw_item,
            favicon_policy="external" if should_process_icon else "none",
            preserve_usage_history=source.preserve_usage_history,
        )
        if item is None:
            rejected += 1
            continue
        key = canonical_http_url(item["url"])
        if key in positions:
            duplicates_in_file += 1
            merge_duplicate_import(result[positions[key]], item)
            continue
        positions[key] = len(result)
        result.append(item)
        if key in existing:
            duplicates_existing += 1

    return {
        "ok": True,
        "items": result,
        "stats": {
            "format": source.format_name,
            "found": len(source.raw_bookmarks),
            "ready": len(result),
            "rejected": rejected,
            "duplicatesInFile": duplicates_in_file,
            "duplicatesExisting": duplicates_existing,
            "new": len(result) - duplicates_existing,
            "favicons": sum(1 for item in result if item["favicon"]),
            "untitled": sum(1 for item in result if not item["title"]),
        },
    }
