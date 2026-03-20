#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def load_entries(script_name: str) -> list[dict]:
    command = [sys.executable, str(SCRIPT_DIR / script_name), "--json"]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError:
        return []

    try:
        data = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return []
    return data if isinstance(data, list) else []


def merged_entries() -> list[dict]:
    entries = []
    grouped_names: defaultdict[str, list[dict]] = defaultdict(list)

    for entry in load_entries("steam.py") + load_entries("lutris.py"):
        grouped_names[entry["name"].lower()].append(entry)

    for _, group in grouped_names.items():
        for entry in group:
            label = entry["name"]
            if len(group) > 1:
                label = f"{entry['name']} <span foreground='gray'>[{entry['backend']}]</span>"
            merged_entry = dict(entry)
            merged_entry["display_name"] = label
            entries.append(merged_entry)

    return sorted(entries, key=lambda item: (item["name"].lower(), item["backend"]))


def emit_rofi(entries: list[dict]) -> None:
    for entry in entries:
        row = f"{entry['display_name']}\t{entry['run_command']}"
        icon_path = entry.get("cover") or entry.get("icon")
        if icon_path:
            row += f"\t\x00icon\x1f{icon_path}"
        print(row)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--rofi-string", action="store_true")
    args = parser.parse_args()

    entries = merged_entries()
    if args.json:
        print(json.dumps(entries, indent=2))
        return 0
    if args.rofi_string:
        emit_rofi(entries)
        return 0

    print(json.dumps(entries, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
