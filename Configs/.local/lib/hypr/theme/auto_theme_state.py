#!/usr/bin/env python3
import fcntl
import json
import os
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Optional

from pyutils.lock_paths import ensure_runtime_root_dir
from pyutils.shell_env import load_shell_assignments, shell_quote_value
from pyutils.xdg_base_dirs import xdg_cache_home, xdg_config_home, xdg_state_home

STATE_FILE = xdg_state_home() / "hypr/auto_theme_state.json"
STATE_TARGETS = ("staterc", "env-overrides", "color_variant")
TMPDIR_PATH = Path(os.environ.get("TMPDIR", "/tmp"))



def active_palette_file() -> Path:
    return xdg_state_home() / "hypr" / "active-palette.json"


def wallpaper_state_file() -> Path:
    return xdg_cache_home() / "hypr" / "wallpaper" / "current" / "wall.set"


def runtime_lock_dir() -> Path:
    return ensure_runtime_root_dir() / "hypr"


def state_data_file(target_file: str) -> Path:
    if target_file not in STATE_TARGETS:
        raise ValueError(f"Unsupported state target '{target_file}'")
    return xdg_state_home() / "hypr" / target_file


def state_lock_file(target_file: str) -> Path:
    return runtime_lock_dir() / f"state-{target_file}.lock"


def load_state(state_file: Path = STATE_FILE) -> dict:
    defaults = {
        "current_mode": "dark",
        "last_change": None,
        "manual_override_until": None,
    }
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text())
            if isinstance(state, dict):
                state.pop("last_prewarm", None)
                state.pop("last_prewarm_pid", None)
                return {**defaults, **state}
        except Exception as exc:
            print(f"Warning: Failed to load state from {state_file}: {exc}", file=sys.stderr)
    return defaults


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, path)


@contextmanager
def held_state_lock(target_file: str):
    lock_file = state_lock_file(target_file)
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock_file, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def set_state_value(var_name: str, var_value: str, target_file: str = "staterc") -> None:
    state_file = state_data_file(target_file)

    if target_file == "color_variant":
        if not var_value:
            raise ValueError("color_variant value required")
        with held_state_lock(target_file):
            atomic_write_text(state_file, f"{var_value}\n")
        return

    if not var_name:
        raise ValueError("state variable name required")

    value_prefix = "export " if target_file == "env-overrides" else ""
    quoted_value = shell_quote_value(str(var_value))
    state_file.parent.mkdir(parents=True, exist_ok=True)

    with held_state_lock(target_file):
        existing_lines = state_file.read_text().splitlines() if state_file.exists() else []
        updated_lines = []
        for line in existing_lines:
            stripped = line.strip()
            if not stripped:
                updated_lines.append(line)
                continue
            normalized = stripped
            if normalized.startswith("export "):
                normalized = normalized[len("export ") :].lstrip()
            if normalized.startswith(f"{var_name}="):
                continue
            updated_lines.append(line)
        updated_lines.append(f"{value_prefix}{var_name}={quoted_value}")
        atomic_write_text(state_file, "\n".join(updated_lines) + "\n")


def save_state(state: dict, state_file: Path = STATE_FILE) -> None:
    atomic_write_text(state_file, json.dumps(state))


def read_staterc() -> dict:
    staterc = state_data_file("staterc")
    if not staterc.exists():
        return {}
    try:
        return load_shell_assignments(staterc)
    except Exception:
        return {}


def read_color_variant_file() -> Optional[str]:
    variant_file = state_data_file("color_variant")
    if variant_file.exists():
        return variant_file.read_text().strip()
    return None


def read_active_palette() -> dict:
    palette_file = active_palette_file()
    if not palette_file.exists():
        return {}
    try:
        data = json.loads(palette_file.read_text())
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def resolve_wallpaper(staterc_values: dict) -> Optional[Path]:
    cache_wall = wallpaper_state_file()
    if cache_wall.exists():
        return cache_wall.resolve()

    theme = staterc_values.get("HYPR_THEME")
    if theme:
        theme_wall = xdg_config_home() / "hypr" / "themes" / theme / "wall.set"
        if theme_wall.exists():
            return theme_wall.resolve()
    return None


def load_state_env(config_file: Path | None = None) -> dict:
    config_file = state_data_file("env-overrides") if config_file is None else config_file
    if not config_file.exists():
        return {}
    try:
        return load_shell_assignments(config_file)
    except Exception:
        return {}


def manual_override_deadline(state: dict) -> Optional[datetime]:
    raw_until = state.get("manual_override_until")
    if not raw_until:
        return None
    try:
        return datetime.fromisoformat(raw_until)
    except Exception:
        state["manual_override_until"] = None
        return None
