#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def main() -> int:
    parser = argparse.ArgumentParser(description="Save and restore Hyprland window sessions.")
    sub = parser.add_subparsers(dest="action", required=True)

    save_p = sub.add_parser("save")
    save_p.add_argument("name", nargs="?", default="default")
    save_p.add_argument("-v", "--verbose", action="store_true")

    restore_p = sub.add_parser("restore")
    restore_p.add_argument("name", nargs="?", default="default")
    restore_p.add_argument("--force", action="store_true", help="launch every saved app instead of moving live windows first")
    restore_p.add_argument("--dry-run", action="store_true")

    sub.add_parser("list")

    delete_p = sub.add_parser("delete")
    delete_p.add_argument("name")

    path_p = sub.add_parser("path")
    path_p.add_argument("name", nargs="?", default="default")

    args = parser.parse_args()
    if args.action == "save":
        from snapshots.capture import save_session
        save_session(args.name, args.verbose)
    elif args.action == "restore":
        from snapshots.restore import restore_session
        if restore_session(args.name, args.force, args.dry_run):
            return 1
    elif args.action == "list":
        from snapshots.storage import list_sessions
        list_sessions()
    elif args.action == "delete":
        from snapshots.storage import delete_session
        delete_session(args.name)
    elif args.action == "path":
        from snapshots.storage import snapshot_path
        print(snapshot_path(args.name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
