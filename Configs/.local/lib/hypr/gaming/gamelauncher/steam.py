#!/usr/bin/env python3
import argparse
import json
import os
import re
from pathlib import Path

XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share")))
DEFAULT_STEAM_ROOTS = [
    XDG_DATA_HOME / "Steam",
    Path.home() / ".steam" / "steam",
    Path.home() / ".var" / "app" / "com.valvesoftware.Steam" / ".local" / "share" / "Steam",
]
EXCLUDE_NAME_RE = re.compile(r"(?i)\b(proton|steam runtime|steamworks|steam client|steam linux runtime|soldier|sniper)\b")


def parse_appmanifest(manifest_path: Path) -> dict:
    content = manifest_path.read_text(errors="ignore")
    appid_match = re.search(r'"appid"\s*"(\d+)"', content)
    name_match = re.search(r'"name"\s*"([^"]+)"', content)
    if not appid_match or not name_match:
        return {}
    return {"id": int(appid_match.group(1)), "name": name_match.group(1)}


def parse_libraryfolders(libraryfolders_path: Path) -> list[Path]:
    libraries: list[Path] = []
    content = libraryfolders_path.read_text(errors="ignore")
    for match in re.finditer(r'"path"\s*"([^"]+)"', content):
        raw_path = match.group(1).replace('\\\\', '\\')
        library_path = Path(os.path.expanduser(raw_path))
        if library_path.exists():
            libraries.append(library_path)
    return libraries


def steamapps_dirs() -> list[Path]:
    directories: list[Path] = []
    for root in DEFAULT_STEAM_ROOTS:
        if not root.exists():
            continue
        libraryfolders = root / "steamapps" / "libraryfolders.vdf"
        directories.append(root / "steamapps")
        if libraryfolders.exists():
            for library_root in parse_libraryfolders(libraryfolders):
                directories.append(library_root / "steamapps")

    seen: set[Path] = set()
    result: list[Path] = []
    for directory in directories:
        resolved = directory.resolve()
        if resolved in seen or not resolved.exists():
            continue
        seen.add(resolved)
        result.append(resolved)
    return result


def steam_cover_path(steamapps_dir: Path, appid: int) -> str:
    candidates = [
        steamapps_dir.parent / "appcache" / "librarycache" / str(appid) / "library_600x900.jpg",
        steamapps_dir.parent / "appcache" / "librarycache" / str(appid) / "header.jpg",
        steamapps_dir.parent / "appcache" / "librarycache" / f"{appid}.jpg",
        steamapps_dir.parent / "appcache" / "librarycache" / f"{appid}_library_600x900.jpg",
        steamapps_dir.parent / "appcache" / "librarycache" / f"{appid}_header.jpg",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return ""


def list_games() -> list[dict]:
    games: list[dict] = []
    seen_ids: set[int] = set()

    for steamapps_dir in steamapps_dirs():
        for manifest in sorted(steamapps_dir.glob("appmanifest_*.acf")):
            game = parse_appmanifest(manifest)
            if not game:
                continue
            if game["id"] in seen_ids or EXCLUDE_NAME_RE.search(game["name"]):
                continue
            seen_ids.add(game["id"])

            cover = steam_cover_path(steamapps_dir, game["id"])
            run_command = f"xdg-open steam://rungameid/{game['id']}"
            entry = {
                "id": game["id"],
                "name": game["name"],
                "backend": "steam",
                "path": str(steamapps_dir),
                "cover": cover,
                "run_command": run_command,
            }
            games.append(entry)

    return sorted(games, key=lambda item: item["name"].lower())


def emit_rofi(entries: list[dict]) -> None:
    for entry in entries:
        row = f"{entry['name']}\t{entry['run_command']}"
        if entry.get("cover"):
            row += f"\t\x00icon\x1f{entry['cover']}"
        print(row)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--detect", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--rofi-string", action="store_true")
    args = parser.parse_args()

    if args.detect:
        print(json.dumps([str(path) for path in steamapps_dirs()], indent=2))
        return 0

    entries = list_games()
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
