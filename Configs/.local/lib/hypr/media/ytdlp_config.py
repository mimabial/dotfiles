from __future__ import annotations

import shlex
import sys
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils.xdg_base_dirs import xdg_config_home


def default_config_path() -> Path:
    config_home = xdg_config_home()
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
