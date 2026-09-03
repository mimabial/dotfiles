#!/usr/bin/env python3
"""Read or change the shared XDG music-library directory."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

from lyrics_paths import absolute_path, music_library_dir

RMPC_CONFIG = Path.home() / ".config/rmpc/config.ron"
RMPC_LYRICS_SETTING = re.compile(
    r"(?m)^(?P<prefix>\s*lyrics_dir:\s*)(?:Some\(.*\)|None),\s*$"
)


def render_rmpc_config(content: str, library: Path) -> str:
    """Mirror the XDG path into rmpc, which only expands a leading tilde."""
    ron_path = json.dumps(f"{library}/", ensure_ascii=False)
    updated, count = RMPC_LYRICS_SETTING.subn(
        lambda match: f"{match.group('prefix')}Some({ron_path}),",
        content,
    )
    if count != 1:
        raise ValueError("expected exactly one lyrics_dir setting in the rmpc config")
    return updated


def update_rmpc_config(library: Path) -> None:
    content = RMPC_CONFIG.read_text(encoding="utf-8")
    updated = render_rmpc_config(content, library)
    if updated == content:
        return

    mode = stat.S_IMODE(RMPC_CONFIG.stat().st_mode)
    fd, temporary = tempfile.mkstemp(
        prefix=f".{RMPC_CONFIG.name}.",
        dir=RMPC_CONFIG.parent,
        text=True,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(updated)
        os.chmod(temporary, mode)
        os.replace(temporary, RMPC_CONFIG)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def export_to_activation_environment(assignment: str) -> None:
    """Publish KEY=VALUE to the DBus activation environment.

    --systemd also updates the systemd user manager where there is one, so this
    covers both inits. Best-effort: the library is already configured on disk by
    the time this runs, and a missing dbus tool must not fail the whole call.
    """
    if not shutil.which("dbus-update-activation-environment"):
        return
    command = ["dbus-update-activation-environment"]
    if Path("/run/systemd/system").is_dir():
        command.append("--systemd")
    command.append(assignment)
    subprocess.run(command, check=False)


def set_music_library(raw_directory: str) -> Path:
    library = absolute_path(raw_directory)
    if library == Path("/"):
        raise ValueError("the filesystem root cannot be used as the music library")
    if not library.is_dir():
        raise ValueError(f"directory does not exist: {library}")

    current_rmpc = RMPC_CONFIG.read_text(encoding="utf-8")
    render_rmpc_config(current_rmpc, library)

    subprocess.run(
        ["xdg-user-dirs-update", "--set", "MUSIC", str(library)],
        check=True,
    )
    update_rmpc_config(library)
    export_to_activation_environment(f"XDG_MUSIC_DIR={library}")
    return library


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="music-library",
        description=(
            "Show or change the XDG music-library directory used by the media tools"
        ),
    )
    parser.add_argument(
        "-s",
        "--set",
        dest="directory",
        metavar="DIRECTORY",
        help="Use an existing directory as the music library",
    )
    args = parser.parse_args()

    try:
        library = (
            set_music_library(args.directory)
            if args.directory is not None
            else music_library_dir()
        )
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"music-library: {exc}", file=sys.stderr)
        return 1

    print(library)
    if args.directory is not None:
        print(
            "Restart MPD to load the new library; RMPC will reload its path.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
