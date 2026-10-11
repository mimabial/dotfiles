from __future__ import annotations

import subprocess
from typing import Any
from urllib.parse import urlsplit

from pyutils import child_process

from .bounded_io import BoundedOutputError, run_bounded_process
from .network_settings import read_network_settings
from .store import read_store_items
from .urls import MAX_URL_BYTES, canonical_http_url, validated_http_url


CLIPBOARD_TIMEOUT_SECONDS = 2

def prepare_bookmark_from_clipboard(
    store_path: str,
    enrich_from_web: bool = False,
    settings_path: str = "",
) -> dict[str, Any]:
    try:
        process = run_bounded_process(
            ["wl-paste", "--no-newline", "--type", "text"],
            max_output_bytes=MAX_URL_BYTES,
            timeout_seconds=CLIPBOARD_TIMEOUT_SECONDS,
        )
        clipboard = process.stdout.decode("utf-8", errors="replace").strip()
    except BoundedOutputError:
        return {"ok": False, "error": "Clipboard text is too large"}
    except (OSError, subprocess.TimeoutExpired):
        return {"ok": False, "error": "Could not read the clipboard"}

    url = validated_http_url(clipboard)
    if not url:
        return {"ok": False, "error": "Clipboard must contain exactly one HTTP(S) URL"}

    key = canonical_http_url(url)
    for item in read_store_items(store_path):
        if canonical_http_url(item.get("url")) == key:
            return {"ok": True, "duplicate": True, "id": str(item.get("id") or ""), "url": url}

    title = ""
    favicon = ""
    if enrich_from_web:
        if not settings_path:
            raise ValueError("Web enrichment requires an explicit settings path")
        from .page_metadata import fetch_page_metadata_in_worker

        title, favicon = fetch_page_metadata_in_worker(url, settings_path)
        if not title:
            title = urlsplit(url).hostname or url

    return {
        "ok": True,
        "duplicate": False,
        "item": {"title": title, "url": url, "tags": [], "keyword": "", "favicon": favicon},
    }


def copy_url_to_clipboard(value: str) -> dict[str, Any]:
    url = validated_http_url(value)
    if not url:
        return {"ok": False, "error": "Could not copy an invalid bookmark URL"}
    try:
        process = child_process.run(
            ["wl-copy", "--type", "text/plain;charset=utf-8"],
            input=url.encode("utf-8"),
            stdout=subprocess.DEVNULL,
            # wl-copy forks a clipboard-serving child. A PIPE here remains
            # open in that child, so subprocess.run waits until its timeout
            # even though the copy succeeded.
            stderr=subprocess.DEVNULL,
            timeout=CLIPBOARD_TIMEOUT_SECONDS,
            check=False,
        )
    except FileNotFoundError:
        return {"ok": False, "error": "Could not copy URL · install wl-clipboard"}
    except (OSError, subprocess.TimeoutExpired):
        return {"ok": False, "error": "Could not copy URL to the clipboard"}
    if process.returncode != 0:
        return {"ok": False, "error": "Could not copy URL to the clipboard"}
    return {"ok": True, "url": url}


def prepare_bookmark_from_clipboard_with_metadata(
    store_path: str, settings_path: str
) -> dict[str, Any]:
    settings = read_network_settings(settings_path)
    return prepare_bookmark_from_clipboard(
        store_path,
        enrich_from_web=settings["networkEnrichment"] is True,
        settings_path=settings_path,
    )
