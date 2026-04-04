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
from pyutils.shell_env import load_shell_assignments
from pyutils.xdg_base_dirs import xdg_config_home, xdg_data_home, xdg_state_home

logger = logger_mod.get_logger()

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
DUNST_SYNC_SCRIPT = os.path.join(os.path.dirname(__file__), "..", "wal", "wal.dunst.sh")
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


def ensure_directory_exists(filepath):
    directory = os.path.dirname(filepath)
    if not os.path.exists(directory):
        os.makedirs(directory)
