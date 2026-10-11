import os
from pathlib import Path


def _absolute_path_from_env(variable: str) -> Path | None:
    value = os.environ.get(variable)
    return Path(value) if value and Path(value).is_absolute() else None


def xdg_cache_home() -> Path:
    return _absolute_path_from_env("XDG_CACHE_HOME") or Path.home() / ".cache"


def xdg_config_home() -> Path:
    return _absolute_path_from_env("XDG_CONFIG_HOME") or Path.home() / ".config"


def xdg_data_home() -> Path:
    return _absolute_path_from_env("XDG_DATA_HOME") or Path.home() / ".local/share"


def xdg_state_home() -> Path:
    return _absolute_path_from_env("XDG_STATE_HOME") or Path.home() / ".local/state"


def xdg_runtime_dir() -> Path | None:
    return _absolute_path_from_env("XDG_RUNTIME_DIR")


def xdg_data_dirs() -> list[Path]:
    configured = [Path(path) for path in os.environ.get("XDG_DATA_DIRS", "").split(":") if Path(path).is_absolute()]
    return configured or [Path("/usr/local/share"), Path("/usr/share")]
