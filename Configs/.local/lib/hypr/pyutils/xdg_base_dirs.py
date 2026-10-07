"""XDG Base Directory Specification variables.

xdg_cache_home(), xdg_config_home(), xdg_data_home(), and xdg_state_home()
return pathlib.Path objects containing the value of the environment variable
named XDG_CACHE_HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, and XDG_STATE_HOME
respectively, or the default defined in the specification if the environment
variable is unset, empty, or contains a relative path rather than absolute
path.

xdg_config_dirs() and xdg_data_dirs() return a list of pathlib.Path
objects containing the value, split on colons, of the environment
variable named XDG_CONFIG_DIRS and XDG_DATA_DIRS respectively, or the
default defined in the specification if the environment variable is
unset or empty. Relative paths are ignored, as per the specification.

xdg_runtime_dir() returns a pathlib.Path object containing the value of
the XDG_RUNTIME_DIR environment variable, or None if the environment
variable is not set, or contains a relative path rather than absolute path.

"""

import os
from pathlib import Path

__all__ = [
    "xdg_cache_home",
    "xdg_config_dirs",
    "xdg_config_home",
    "xdg_data_dirs",
    "xdg_data_home",
    "xdg_runtime_dir",
    "xdg_state_home",
]


def _path_from_env(variable: str, default: Path) -> Path:
    if (value := os.environ.get(variable)) and (path := Path(value)).is_absolute():
        return path
    return default


def _paths_from_env(variable: str, default: list[Path]) -> list[Path]:
    if value := os.environ.get(variable):
        paths = [Path(path) for path in value.split(":") if Path(path).is_absolute()]
        if paths:
            return paths
    return default


def xdg_cache_home() -> Path:
    return _path_from_env("XDG_CACHE_HOME", Path.home() / ".cache")


def xdg_config_dirs() -> list[Path]:
    return _paths_from_env("XDG_CONFIG_DIRS", [Path("/etc/xdg")])


def xdg_config_home() -> Path:
    return _path_from_env("XDG_CONFIG_HOME", Path.home() / ".config")


def xdg_data_dirs() -> list[Path]:
    return _paths_from_env(
        "XDG_DATA_DIRS",
        [Path(path) for path in "/usr/local/share/:/usr/share/".split(":")],
    )


def xdg_data_home() -> Path:
    return _path_from_env("XDG_DATA_HOME", Path.home() / ".local" / "share")


def xdg_runtime_dir() -> Path | None:
    if (value := os.getenv("XDG_RUNTIME_DIR")) and (path := Path(value)).is_absolute():
        return path
    return None


def xdg_state_home() -> Path:
    return _path_from_env("XDG_STATE_HOME", Path.home() / ".local" / "state")


def user_lib_dir() -> Path:
    return Path.home() / ".local" / "lib"
