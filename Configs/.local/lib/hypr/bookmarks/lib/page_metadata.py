from __future__ import annotations

import json
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlsplit, urlunsplit

from .bounded_io import BoundedOutputError, run_bounded_process
from .favicons import MAX_ICON_INPUT_BYTES, image_to_png_data_url, stored_png_data_url
from .network_settings import read_network_settings
from .public_http import fetch_public_http_bytes, same_http_origin
from .records import MAX_TITLE_CHARS
from .urls import MAX_URL_BYTES, MAX_URL_CHARS, canonical_http_url, validated_http_url


ICON_FETCH_TIMEOUT_SECONDS = 3
MAX_HTML_BYTES = 1_000_000
FETCHED_HTML_SNIFF_BYTES = 2048
CHARSET_SNIFF_BYTES = 8192
MAX_ICON_CANDIDATES = 8
MAX_ICON_FETCHES = 4
MAX_ENRICHMENT_SECONDS = 15
MAX_ENRICHMENT_OUTPUT_BYTES = 256 * 1024


class PageMetadataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.in_title = False
        self.title_parts: list[str] = []
        self.title_length = 0
        self.open_graph_title = ""
        self.icons: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {str(k).lower(): str(v or "") for k, v in attrs}
        if tag.lower() == "title":
            self.in_title = True
        elif tag.lower() == "meta" and values.get("property", "").lower() == "og:title":
            self.open_graph_title = values.get("content", "").strip()[:MAX_TITLE_CHARS]
        elif tag.lower() == "link" and "icon" in values.get("rel", "").lower().split():
            href = values.get("href", "")
            if (
                href
                and len(href) <= MAX_URL_CHARS
                and len(self.icons) < MAX_ICON_CANDIDATES
            ):
                self.icons.append(href)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "title":
            self.in_title = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            remaining = MAX_TITLE_CHARS - self.title_length
            if remaining > 0:
                part = data[:remaining]
                self.title_parts.append(part)
                self.title_length += len(part)

    @property
    def title(self) -> str:
        title = " ".join("".join(self.title_parts).split())
        return (title or self.open_graph_title)[:MAX_TITLE_CHARS]


def enrich_url_from_web(url: str) -> dict[str, Any]:
    """Runs inside the time-bounded worker process."""
    url = validated_http_url(url)
    if not url:
        raise ValueError("Web enrichment requires one valid HTTP(S) URL")

    hostname = urlsplit(url).hostname or url
    title = hostname
    favicon = ""
    try:
        raw, final_url, content_type = fetch_public_http_bytes(
            url, MAX_HTML_BYTES, "text/html,application/xhtml+xml"
        )
        if (
            content_type in ("text/html", "application/xhtml+xml")
            or b"<html" in raw[:FETCHED_HTML_SNIFF_BYTES].lower()
        ):
            charset_match = re.search(
                br"charset\s*=\s*['\"]?([A-Za-z0-9._-]+)", raw[:CHARSET_SNIFF_BYTES], re.I
            )
            charset = (
                charset_match.group(1).decode("ascii", errors="ignore")
                if charset_match
                else "utf-8"
            )
            page = raw.decode(charset, errors="replace")
            parser = PageMetadataParser()
            parser.feed(page)
            title = parser.title or hostname
            icon_candidates = [
                candidate
                for value in parser.icons
                if validated_http_url(candidate := urljoin(final_url, value))
                and same_http_origin(candidate, final_url)
            ]
            icon_candidates.append(urljoin(final_url, "/favicon.ico"))
            seen_icons: set[str] = set()
            for icon_url in icon_candidates[:MAX_ICON_FETCHES]:
                key = canonical_http_url(
                    urlunsplit(urlsplit(icon_url)._replace(fragment=""))
                )
                if not key or key in seen_icons:
                    continue
                seen_icons.add(key)
                try:
                    icon_raw, _, _ = fetch_public_http_bytes(
                        icon_url,
                        MAX_ICON_INPUT_BYTES,
                        "image/*",
                        timeout_seconds=ICON_FETCH_TIMEOUT_SECONDS,
                        redirect_origin=final_url,
                    )
                    favicon = image_to_png_data_url(icon_raw)
                    if favicon:
                        break
                except (OSError, ValueError):
                    continue
    except (OSError, ValueError, LookupError):
        pass
    return {"ok": True, "title": title, "favicon": favicon}


def fetch_page_metadata_in_worker(url: str, settings_path: str) -> tuple[str, str]:
    """All network and decoder work sits behind a hard wall-clock limit."""
    try:
        process = run_bounded_process(
            [
                sys.executable,
                str(Path(__file__).resolve().parents[1] / "commands.py"),
                "enrich-url",
                settings_path,
            ],
            input_data=url.encode("utf-8"),
            max_output_bytes=MAX_ENRICHMENT_OUTPUT_BYTES,
            timeout_seconds=MAX_ENRICHMENT_SECONDS,
        )
    except (OSError, BoundedOutputError, subprocess.TimeoutExpired):
        return "", ""
    if process.returncode != 0:
        return "", ""
    try:
        result = json.loads(process.stdout)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return "", ""
    if not isinstance(result, dict) or result.get("ok") is not True:
        return "", ""
    title = str(result.get("title") or "").strip()
    if len(title) > MAX_TITLE_CHARS:
        title = ""
    return title, stored_png_data_url(result.get("favicon"))


def enrich_stdin_url(settings_path: str) -> dict[str, Any]:
    if read_network_settings(settings_path)["networkEnrichment"] is not True:
        raise ValueError("Web enrichment is disabled")
    raw_url = sys.stdin.buffer.read(MAX_URL_BYTES + 1)
    if len(raw_url) > MAX_URL_BYTES:
        raise ValueError("Web enrichment URL is too large")
    return enrich_url_from_web(raw_url.decode("utf-8"))
