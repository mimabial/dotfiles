from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .bounded_io import atomic_write, existing_regular_mode, read_limited_text


MAX_SETTINGS_BYTES = 16 * 1024
SETTINGS_VERSION = 1


def read_network_settings(settings_path: str) -> dict[str, Any]:
    path = Path(settings_path).expanduser()
    try:
        raw = read_limited_text(
            path,
            MAX_SETTINGS_BYTES,
            "Bookmarks settings",
            follow_symlinks=False,
        )
    except FileNotFoundError:
        return {"version": SETTINGS_VERSION, "networkEnrichment": False}
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("version") != SETTINGS_VERSION:
        raise ValueError("Bookmarks settings use an unsupported format")
    network_enrichment = data.get("networkEnrichment", False)
    if not isinstance(network_enrichment, bool):
        raise ValueError("Bookmarks settings contain an invalid network choice")
    return {
        "version": SETTINGS_VERSION,
        "networkEnrichment": network_enrichment,
    }


def write_network_settings(settings_path: str, settings: dict[str, Any]) -> None:
    network_enrichment = settings.get("networkEnrichment", False)
    if not isinstance(network_enrichment, bool):
        raise ValueError("Invalid network choice")
    path = Path(settings_path).expanduser()
    if not path.parent.exists():
        path.parent.mkdir(parents=True, mode=0o700)
    mode = existing_regular_mode(path, "Bookmarks settings", 0o600)
    value = json.dumps(
        {
            "version": SETTINGS_VERSION,
            "networkEnrichment": network_enrichment,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ) + "\n"
    atomic_write(path, value, mode)


def network_enrichment_command(operation: str, settings_path: str) -> dict[str, Any]:
    settings = read_network_settings(settings_path)
    if operation == "status":
        return {"ok": True, "enabled": settings["networkEnrichment"]}
    if operation not in ("enable", "disable"):
        raise ValueError("network enrichment operation must be status, enable, or disable")
    settings["networkEnrichment"] = operation == "enable"
    write_network_settings(settings_path, settings)
    return {"ok": True, "enabled": settings["networkEnrichment"]}
