from __future__ import annotations

import math
import re
from typing import Any

from .urls import validated_http_url


MAX_TITLE_CHARS = 2048
MAX_IDENTIFIER_CHARS = 256
MAX_TAGS = 64
MAX_TAG_CHARS = 128
MAX_KEYWORD_CHARS = 128


def normalize_tags(value: Any) -> list[str]:
    if isinstance(value, list):
        source = value[:MAX_TAGS]
    else:
        serialized = str(value or "")
        if len(serialized) > MAX_TAGS * (MAX_TAG_CHARS + 1):
            return []
        source = serialized.split(",", MAX_TAGS)[:MAX_TAGS]
    result: list[str] = []
    seen: set[str] = set()
    for item in source:
        tag = str(item).strip()
        key = tag.casefold()
        if tag and len(tag) <= MAX_TAG_CHARS and key not in seen:
            result.append(tag)
            seen.add(key)
    return result


def normalize_keyword(value: Any) -> str:
    keyword = str(value or "").strip()
    return (
        keyword
        if keyword and len(keyword) <= MAX_KEYWORD_CHARS and not re.search(r"\s", keyword)
        else ""
    )


def normalize_bookmark(
    item: Any,
    favicon_policy: str = "stored",
    preserve_usage_history: bool = True,
) -> dict[str, Any] | None:
    if not isinstance(item, dict):
        return None
    url = validated_http_url(item.get("url") or item.get("href"))
    if not url:
        return None
    title = str(item.get("title") or "").strip()
    if len(title) > MAX_TITLE_CHARS:
        return None
    if favicon_policy == "external":
        from .favicons import embedded_icon_to_png_data_url

        favicon = embedded_icon_to_png_data_url(item.get("iconSource") or item.get("favicon"))
    elif favicon_policy == "none":
        favicon = ""
    elif favicon_policy == "stored":
        from .favicons import stored_png_data_url

        favicon = stored_png_data_url(item.get("favicon"))
    else:
        raise ValueError("Invalid favicon processing policy")
    try:
        usage_score = float(item.get("usageScore") or 0) if preserve_usage_history else 0.0
        if not math.isfinite(usage_score) or usage_score < 0:
            usage_score = 0.0
    except (TypeError, ValueError):
        usage_score = 0.0
    try:
        last_opened_at = int(item.get("lastOpenedAt") or 0) if preserve_usage_history else 0
        if last_opened_at < 0:
            last_opened_at = 0
    except (TypeError, ValueError, OverflowError):
        last_opened_at = 0
    return {
        "title": title,
        "url": url,
        "tags": normalize_tags(item.get("tags")),
        "keyword": normalize_keyword(item.get("keyword") or item.get("shortcuturl")),
        "favicon": favicon,
        "usageScore": usage_score,
        "lastOpenedAt": last_opened_at,
        "source": "firefox" if item.get("source") == "firefox" else "",
    }
