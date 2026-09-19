#!/usr/bin/env python3
# Resolve which shell a theme pack uses.
# Underscore-prefixed, so hypr-theme's renderer scan skips it.

import os
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pyutils.shell_env import load_shell_assignments

DEFAULT_SHELL = "flat"

CONFIG_HOME = Path(os.environ.get("HYPR_CONFIG_HOME", Path.home() / ".config/hypr"))
STATE_HOME = Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr"))
SHELLS_DIR = CONFIG_HOME / "kvantum" / "shells"
THEMES_DIR = CONFIG_HOME / "themes"


def active_pack(palette=None):
    """The pack naming the shell. In wallpaper mode the palette carries no pack,
    so fall back to staterc, which still records the selected theme."""
    pack = os.environ.get("HYPR_THEME", "")
    if pack:
        return pack
    source = (palette or {}).get("source", "")
    if source.startswith("theme:"):
        return source.removeprefix("theme:")
    return load_shell_assignments(STATE_HOME / "staterc").get("HYPR_THEME", "")


def shell_name(pack):
    toml_file = THEMES_DIR / pack / "palette.toml" if pack else None
    if toml_file and toml_file.is_file():
        try:
            declared = tomllib.loads(toml_file.read_text()).get("kvantum-shell")
        except (OSError, tomllib.TOMLDecodeError):
            declared = None
        if isinstance(declared, str) and (SHELLS_DIR / declared).is_dir():
            return declared
    return DEFAULT_SHELL


def shell_dir(palette=None):
    return SHELLS_DIR / shell_name(active_pack(palette))


def shell_files(palette=None):
    """(kvconfig, map), each None when absent."""
    base = shell_dir(palette)
    paths = (base / "shell.kvconfig", base / "shell.map")
    return tuple(path if path.is_file() else None for path in paths)
