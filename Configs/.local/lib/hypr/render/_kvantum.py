#!/usr/bin/env python3
# Underscore-prefixed, so hypr-theme's renderer scan skips it.

import os
import sys
import tomllib
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pyutils.shell_env import load_shell_assignments
from _common import CONFIG_HOME, STATE_HOME

DEFAULT_KVANTUM_SHELL = "flat"

KVANTUM_SHELLS_DIR = CONFIG_HOME / "kvantum" / "shells"
THEMES_DIR = CONFIG_HOME / "themes"


def active_theme_pack(palette=None):
    """The pack naming the shell. In wallpaper mode the palette carries no pack,
    so fall back to staterc, which still records the selected theme."""
    pack = os.environ.get("HYPR_THEME", "")
    if pack:
        return pack
    source = (palette or {}).get("source", "")
    if source.startswith("theme:"):
        return source.removeprefix("theme:")
    return load_shell_assignments(STATE_HOME / "staterc").get("HYPR_THEME", "")


def kvantum_shell_name(pack):
    toml_file = THEMES_DIR / pack / "palette.toml" if pack else None
    if toml_file and toml_file.is_file():
        try:
            declared = tomllib.loads(toml_file.read_text()).get("kvantum-shell")
        except (OSError, tomllib.TOMLDecodeError):
            declared = None
        if isinstance(declared, str) and (KVANTUM_SHELLS_DIR / declared).is_dir():
            return declared
    return DEFAULT_KVANTUM_SHELL


class KvantumColorFiles(NamedTuple):
    kvconfig_path: Path | None
    color_map_path: Path | None


def resolve_kvantum_color_files(palette=None) -> KvantumColorFiles:
    shell_dir = KVANTUM_SHELLS_DIR / kvantum_shell_name(active_theme_pack(palette))
    config_file, color_map_file = shell_dir / "shell.kvconfig", shell_dir / "shell.map"
    return KvantumColorFiles(config_file if config_file.is_file() else None, color_map_file if color_map_file.is_file() else None)
