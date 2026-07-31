"""Small, safe subset of yt-dlp configuration shared by metadata probes."""

from __future__ import annotations

import os
import shlex
from functools import lru_cache
from pathlib import Path


def default_config_path() -> Path:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "yt-dlp" / "config"


@lru_cache(maxsize=4)
def _read_auth_args(config_path: str) -> tuple[str, ...]:
    """Read only cookie authentication, never download or output options."""
    try:
        tokens: list[str] = []
        with Path(config_path).open(encoding="utf-8") as config:
            for raw_line in config:
                line = raw_line.strip()
                if line and not line.startswith("#"):
                    tokens.extend(shlex.split(line))
    except (OSError, ValueError):
        return ()

    args: list[str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in ("--cookies-from-browser", "--cookies"):
            if index + 1 < len(tokens):
                args.extend((token, tokens[index + 1]))
            index += 2
            continue
        if token.startswith(("--cookies-from-browser=", "--cookies=")):
            args.append(token)
        index += 1
    return tuple(args)


def ytdlp_auth_args(config_path: Path | None = None) -> list[str]:
    path = config_path or default_config_path()
    return list(_read_auth_args(str(path)))
