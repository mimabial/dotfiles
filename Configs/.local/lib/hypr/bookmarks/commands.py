#!/usr/bin/env python3
from __future__ import annotations

import json
import signal
import sys
from importlib import import_module
from pathlib import Path
from typing import Any


COMMANDS = {
    'import': (('FILE', 'STORE'), 'imports', 'prepare_bookmark_import'),
    'firefox-import': (('PLACES_DB', 'STORE'), 'firefox_sync', 'import_firefox'),
    'firefox-sync': (('STORE',), 'firefox_sync', 'sync_discovered_firefox'),
    'store-load': (('STORE',), 'store', 'load_store_document'),
    'store-save': (('STORE',), 'store', 'save_store_from_stdin'),
    'clipboard': (('STORE',), 'clipboard', 'prepare_bookmark_from_clipboard'),
    'clipboard-enrich': (('STORE', 'SETTINGS'), 'clipboard', 'prepare_bookmark_from_clipboard_with_metadata'),
    'enrich-url': (('SETTINGS',), 'page_metadata', 'enrich_stdin_url'),
    'copy': (('URL',), 'clipboard', 'copy_url_to_clipboard'),
    'browsers': ((), 'browsers', 'discover_browsers'),
    'backup': (('STORE',), 'store', 'create_and_prune_store_backups'),
    'network-enrichment': (('{status|enable|disable}', 'SETTINGS'), 'network_settings', 'network_enrichment_command'),
}

USAGE = "usage: " + Path(__file__).name + " " + " | ".join(
    " ".join((action, *argument_names))
    for action, (argument_names, _module, _handler) in COMMANDS.items()
)


def dispatch(argv: list[str]) -> dict[str, Any]:
    if not argv or argv[0] not in COMMANDS:
        raise ValueError(USAGE)
    action, *arguments = argv
    argument_names, module_name, handler_name = COMMANDS[action]
    if len(arguments) != len(argument_names):
        raise ValueError(USAGE)
    handler = getattr(import_module("lib." + module_name), handler_name)
    return handler(*arguments)


def main() -> int:
    # Quickshell terminates helpers when a transient dialog closes. Raising
    # SystemExit lets active bounded subprocesses run their cleanup blocks and
    # terminate their entire process groups instead of leaving descendants.
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(128 + signum))
    signal.signal(signal.SIGINT, lambda signum, frame: sys.exit(128 + signum))
    try:
        result = dispatch(sys.argv[1:])
    except (IndexError, KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        result = {"ok": False, "error": str(error) or "Bookmark operation failed"}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
