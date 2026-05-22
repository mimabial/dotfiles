#!/usr/bin/env python3
import hashlib
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyutils.logger as logger_mod
from pyutils.lock_paths import runtime_lock_path
from pyutils.shell_env import load_shell_assignments
from pyutils.xdg_base_dirs import xdg_config_home, xdg_data_home, xdg_state_home

logger = logger_mod.get_logger()

# Lock-path topology (shared so all waybar_* modules agree):
#   WAYBAR_LOCK         - PID file naming the live waybar process.
#   WAYBAR_OP_LOCK      - serializes start/stop/restart across all callers.
#   WAYBAR_WATCH_LOCK   - held by the active watcher process; if held, the
#                         apply path defers restarts to the watcher.
#   WAYBAR_WATCH_META   - watcher PID + start time + cmd, advisory only.
#   THEME_UPDATE_LOCK   - held by theme.apply.sh during a theme switch; the
#                         watcher batches events while it's held.
#   THEME_UPDATE_META   - theme/apply paths write reload ownership hints here.
#                         waybar_reload=direct means skip watcher restart;
#                         waybar_reload=css-hot means classify batched events.
WAYBAR_LOCK = runtime_lock_path("waybar")
WAYBAR_OP_LOCK = runtime_lock_path("waybar_op")
WAYBAR_WATCH_LOCK = runtime_lock_path("waybar_watch")
WAYBAR_WATCH_META = runtime_lock_path("waybar_watch_meta")
THEME_UPDATE_LOCK = runtime_lock_path("theme_update")
THEME_UPDATE_META = runtime_lock_path("theme_update_meta")

CONFIG_WAYBAR_DIR = Path(xdg_config_home()) / "waybar"
DATA_WAYBAR_DIR = Path(xdg_data_home()) / "waybar"
CONFIG_ROFI_DIR = Path(xdg_config_home()) / "rofi"
DATA_ROFI_DIR = Path(xdg_data_home()) / "rofi"

MODULE_DIRS = [
    os.path.join(str(CONFIG_WAYBAR_DIR), "modules"),
    os.path.join(str(DATA_WAYBAR_DIR), "modules"),
    os.path.join("/", "usr", "local", "share", "waybar", "modules"),
    os.path.join("/", "usr", "share", "waybar", "modules"),
]

LAYOUT_DIRS = [
    os.path.join(str(CONFIG_WAYBAR_DIR), "layouts"),
    os.path.join(str(DATA_WAYBAR_DIR), "layouts"),
    os.path.join("/", "usr", "local", "share", "waybar", "layouts"),
    os.path.join("/", "usr", "share", "waybar", "layouts"),
]

LAYOUT_IGNORE = ["test.jsonc", "dock#sample.jsonc"]

STYLE_DIRS = [
    os.path.join(str(CONFIG_WAYBAR_DIR), "styles"),
    os.path.join(str(DATA_WAYBAR_DIR), "styles"),
]

INCLUDES_DIRS = [
    os.path.join(str(CONFIG_WAYBAR_DIR), "includes"),
    os.path.join(str(DATA_WAYBAR_DIR), "includes"),
    os.path.join("/", "usr", "local", "share", "waybar", "includes"),
    os.path.join("/", "usr", "share", "waybar", "includes"),
]

CONFIG_JSONC = CONFIG_WAYBAR_DIR / "config.jsonc"
STATE_FILE = Path(os.path.join(str(xdg_state_home()), "hypr", "staterc"))
HYPR_ENV_OVERRIDES = Path(os.path.join(str(xdg_state_home()), "hypr", "env-overrides"))
DUNST_SYNC_SCRIPT = os.path.join(os.path.dirname(__file__), "..", "render", "dunst.py")
WATCHED_SUFFIXES = {".css", ".json", ".jsonc"}


def source_env_file(filepath):
    try:
        for key, value in load_shell_assignments(filepath).items():
            os.environ[key] = value
    except FileNotFoundError:
        return


def get_file_hash(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as file:
        while chunk := file.read(8192):
            sha256.update(chunk)
    return sha256.hexdigest()


def atomic_write_text(filepath, content):
    filepath = os.fspath(filepath)
    directory = os.path.dirname(filepath)
    os.makedirs(directory, exist_ok=True)
    prefix = f".tmp.{os.path.basename(filepath)}."
    fd, tmp_path = tempfile.mkstemp(prefix=prefix, dir=directory)
    try:
        with os.fdopen(fd, "w") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        os.replace(tmp_path, filepath)
    finally:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass


def atomic_write_json(filepath, data):
    content = json.dumps(data, indent=4) + "\n"
    atomic_write_text(filepath, content)


def atomic_copy_file(src, dest):
    src = os.fspath(src)
    dest = os.fspath(dest)
    directory = os.path.dirname(dest)
    os.makedirs(directory, exist_ok=True)
    prefix = f".tmp.{os.path.basename(dest)}."
    fd, tmp_path = tempfile.mkstemp(prefix=prefix, dir=directory)
    os.close(fd)
    try:
        shutil.copy2(src, tmp_path)
        os.replace(tmp_path, dest)
    finally:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass


# Banner prefixed onto the generated CONFIG_JSONC so users who open it see
# that their edits will be overwritten and learn where the source of truth is.
# JSONC `//` comments are tolerated by Waybar's parser.
CONFIG_JSONC_BANNER = (
    "// GENERATED FILE — DO NOT EDIT.\n"
    "// This file is overwritten on every layout switch and theme apply.\n"
    "// Edit a file in $XDG_CONFIG_HOME/waybar/layouts/ instead, then run\n"
    "// `hyprshell waybar.py --update --set <layout>` to install it as the\n"
    "// active config. See waybar/STATE.md for the layout pipeline.\n"
    "//\n"
)


def install_layout_as_active_config(layout_path):
    """Atomically replace CONFIG_JSONC with a layout file's content, prefixed
    with CONFIG_JSONC_BANNER. All write paths that point Waybar at a layout
    must go through this helper so the banner is never bypassed — users
    opening config.jsonc see the warning regardless of which code path wrote
    it."""
    with open(layout_path, "r") as src:
        layout_content = src.read()
    atomic_write_text(CONFIG_JSONC, CONFIG_JSONC_BANNER + layout_content)


def get_active_config_layout_hash():
    """Hash of CONFIG_JSONC's layout content, excluding the generated banner.
    Used by layout-recovery to identify which layout file is currently active
    by comparison against bare layout-file hashes from get_file_hash.

    Falls back to a whole-file hash when the banner is absent (pre-banner
    config from an older version, or a hand-edited file). Returns None if
    CONFIG_JSONC does not exist."""
    if not CONFIG_JSONC.exists():
        return None
    with open(CONFIG_JSONC, "rb") as file:
        content = file.read()
    banner_bytes = CONFIG_JSONC_BANNER.encode("utf-8")
    if content.startswith(banner_bytes):
        content = content[len(banner_bytes):]
    return hashlib.sha256(content).hexdigest()


def ensure_directory_exists(filepath):
    directory = os.path.dirname(filepath)
    if not os.path.exists(directory):
        os.makedirs(directory)
