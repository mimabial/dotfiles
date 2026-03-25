#!/usr/bin/env python3
import fcntl
import glob
import json
import os
import sys
from contextlib import contextmanager

from waybar_shared import (
    CONFIG_JSONC,
    CONFIG_ROFI_DIR,
    DATA_ROFI_DIR,
    HYPR_ENV_OVERRIDES,
    LAYOUT_DIRS,
    LAYOUT_IGNORE,
    STATE_FILE,
    STYLE_DIRS,
    atomic_copy_file,
    atomic_write_text,
    get_file_hash,
    logger,
)

STATE_LOCK_FILE = STATE_FILE.with_name(f".{STATE_FILE.name}.waybar.lock")


@contextmanager
def state_write_lock():
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_LOCK_FILE, "a+") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def _load_state_lines():
    if not STATE_FILE.exists():
        return []

    with open(STATE_FILE, "r") as file:
        return [line.strip() for line in file if line.strip()]


def _write_state_lines(lines):
    if not lines:
        atomic_write_text(STATE_FILE, "")
        return
    atomic_write_text(STATE_FILE, "\n".join(lines) + "\n")


def _state_map_from_lines(lines):
    state_map = {}
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        state_map[key] = value
    return state_map


def _merge_state_lines(existing_lines, values):
    merged_lines = []
    seen_keys = set()
    for line in existing_lines:
        try:
            current_key = line.split("=", 1)[0]
            if current_key in values or current_key in seen_keys:
                continue
            merged_lines.append(line)
            seen_keys.add(current_key)
        except Exception:
            merged_lines.append(line)

    for key, value in values.items():
        merged_lines.append(f"{key}={value}")

    return merged_lines


def find_layout_files():
    """Recursively find all layout files in the specified directories."""
    layouts = {}
    for layout_dir in reversed(LAYOUT_DIRS):
        if not os.path.isdir(layout_dir):
            continue
        for root, _, files in os.walk(layout_dir):
            for file in files:
                if file.endswith(".jsonc") and file not in LAYOUT_IGNORE:
                    path = os.path.join(root, file)
                    relative_path = os.path.relpath(path, start=layout_dir)
                    layouts[relative_path] = path
    return [layouts[key] for key in sorted(layouts)]


def resolve_rofi_theme(theme_name):
    """Resolve a rofi theme file from user overrides first, then shared stock."""
    if not theme_name:
        return theme_name

    if os.path.isfile(theme_name):
        return theme_name

    candidates = [
        CONFIG_ROFI_DIR / "themes" / f"{theme_name}.rasi",
        CONFIG_ROFI_DIR / "themes" / theme_name,
        CONFIG_ROFI_DIR / f"{theme_name}.rasi",
        CONFIG_ROFI_DIR / theme_name,
        DATA_ROFI_DIR / "themes" / f"{theme_name}.rasi",
        DATA_ROFI_DIR / "themes" / theme_name,
        DATA_ROFI_DIR / f"{theme_name}.rasi",
        DATA_ROFI_DIR / theme_name,
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return theme_name


def get_state_value(key, default=None):
    """Get a value from the state file."""
    if not STATE_FILE.exists():
        return default

    with open(STATE_FILE, "r") as file:
        for line in file:
            if line.startswith(f"{key}="):
                return line.split("=", 1)[1].strip()
    return default


def get_config_value(key, default=None):
    """Get a value from the config file or state file."""
    if HYPR_ENV_OVERRIDES.exists():
        with open(HYPR_ENV_OVERRIDES, "r") as file:
            for line in file:
                clean_line = line.strip()
                if clean_line.startswith("export "):
                    clean_line = clean_line[7:]
                if clean_line.startswith(f"{key}="):
                    return clean_line.split("=", 1)[1].strip()
    return default


def set_state_value(key, value):
    """Set or update one value in the state file, removing duplicates atomically."""
    return set_state_values({key: value})


def set_state_values(values):
    """Set or update multiple values in the state file in one locked atomic write."""
    if not values:
        return True

    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)

    with state_write_lock():
        existing_lines = _load_state_lines()
        _write_state_lines(_merge_state_lines(existing_lines, values))

    return True


def get_current_layout_from_config(persist_state=True):
    """Get the current layout from state, then recover from the generated config if needed."""
    logger.debug("Getting current layout")

    layout_path = get_state_value("WAYBAR_LAYOUT_PATH")
    if layout_path and os.path.exists(layout_path):
        logger.debug(f"Found current layout in state file: {layout_path}")
        return layout_path

    layout_name = get_state_value("WAYBAR_LAYOUT_NAME")
    if layout_name:
        layouts = find_layout_files()
        for layout in layouts:
            if os.path.basename(layout).replace(".jsonc", "") == layout_name:
                logger.debug(f"Found current layout by name in state file: {layout}")
                return layout

    logger.debug("Recovering current layout from config hash")
    logger.debug(f"Checking config: {CONFIG_JSONC}")

    layouts = find_layout_files()
    if not layouts:
        logger.error("No layout files found")
        return None

    if not CONFIG_JSONC.exists():
        logger.debug("Config file not found, using first available layout")
        CONFIG_JSONC.parent.mkdir(parents=True, exist_ok=True)

        layout = layouts[0]
        layout_name = os.path.basename(layout).replace(".jsonc", "")
        if persist_state:
            set_state_values(
                {
                    "WAYBAR_LAYOUT_PATH": layout,
                    "WAYBAR_LAYOUT_NAME": layout_name,
                }
            )

        atomic_copy_file(layout, CONFIG_JSONC)
        logger.debug(f"Created config.jsonc with first layout: {layout}")
        return layout

    config_hash = get_file_hash(CONFIG_JSONC)
    for layout_file in layouts:
        if get_file_hash(layout_file) == config_hash:
            logger.debug(f"Found current layout by hash: {layout_file}")
            layout_name = os.path.basename(layout_file).replace(".jsonc", "")
            if persist_state:
                set_state_values(
                    {
                        "WAYBAR_LAYOUT_PATH": layout_file,
                        "WAYBAR_LAYOUT_NAME": layout_name,
                    }
                )
            return layout_file

    logger.debug("No current layout found by hash comparison, using first layout")
    layout = layouts[0]
    layout_name = os.path.basename(layout).replace(".jsonc", "")
    if persist_state:
        set_state_values(
            {
                "WAYBAR_LAYOUT_PATH": layout,
                "WAYBAR_LAYOUT_NAME": layout_name,
            }
        )
    atomic_copy_file(layout, CONFIG_JSONC)
    logger.debug(f"Updated config.jsonc with layout: {layout}")
    return layout


def ensure_state_file():
    """Ensure the state file has the necessary entries."""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)

    logger.debug(f"Ensuring state file exists at: {STATE_FILE}")

    with state_write_lock():
        lines = _load_state_lines()
        state_map = _state_map_from_lines(lines)

        layout_path_value = state_map.get("WAYBAR_LAYOUT_PATH", "")
        layout_name_value = state_map.get("WAYBAR_LAYOUT_NAME", "")
        style_path_value = state_map.get("WAYBAR_STYLE_PATH", "")

        layout_path_exists = bool(layout_path_value)
        layout_name_exists = bool(layout_name_value)
        style_path_exists = bool(style_path_value)
        style_path_invalid = bool(style_path_value) and not os.path.exists(style_path_value)

        if STATE_FILE.exists() and layout_path_exists and layout_name_exists and style_path_exists and not style_path_invalid:
            return

        logger.debug("State file is missing entries, initializing or updating it")
        current_layout = get_current_layout_from_config(persist_state=False)
        if not current_layout:
            logger.warning("No layout found to write to state file")
            if not STATE_FILE.exists():
                _write_state_lines(lines)
            return

        layout_name = os.path.basename(current_layout).replace(".jsonc", "")
        style_path = resolve_style_path(current_layout)
        updates = {}
        if not layout_path_exists:
            updates["WAYBAR_LAYOUT_PATH"] = current_layout
            logger.debug(f"Added WAYBAR_LAYOUT_PATH={current_layout}")
        if not layout_name_exists:
            updates["WAYBAR_LAYOUT_NAME"] = layout_name
            logger.debug(f"Added WAYBAR_LAYOUT_NAME={layout_name}")
        if not style_path_exists or style_path_invalid:
            updates["WAYBAR_STYLE_PATH"] = style_path
            if style_path_invalid:
                logger.debug(f"Replaced stale WAYBAR_STYLE_PATH={style_path}")
            else:
                logger.debug(f"Added WAYBAR_STYLE_PATH={style_path}")

        if updates or not STATE_FILE.exists():
            _write_state_lines(_merge_state_lines(lines, updates))


def resolve_style_path(layout_path):
    """Resolve the style path based on the layout path."""
    name = os.path.basename(layout_path).replace(".jsonc", "")
    dir_name = os.path.basename(os.path.dirname(layout_path))

    for style_dir in STYLE_DIRS:
        style_path = glob.glob(os.path.join(style_dir, f"{name}*.css"))
        if style_path:
            logger.debug(f"Resolved style path: {style_path[0]}")
            return style_path[0]

        basename_without_hash = name.split("#")[0]
        style_path = glob.glob(os.path.join(style_dir, f"{basename_without_hash}*.css"))
        if style_path:
            logger.debug(f"Resolved style path with #: {style_path[0]}")
            return style_path[0]

        if dir_name:
            style_path = glob.glob(os.path.join(style_dir, f"{dir_name}*.css"))
            if style_path:
                logger.debug(f"Resolved style path from directory name: {style_path[0]}")
                return style_path[0]

    for style_dir in STYLE_DIRS:
        default_path = os.path.join(style_dir, "defaults.css")
        if os.path.exists(default_path):
            logger.debug(f"Using default style: {default_path}")
            return default_path

    logger.warning("No default style found in any style directory")
    return os.path.join(STYLE_DIRS[0], "defaults.css")


def list_layouts():
    """List all layouts with their matching styles."""
    layouts = find_layout_files()
    layout_style_pairs = []

    for layout in layouts:
        if "/backup/" in layout or "\\backup\\" in layout:
            continue
        for layout_dir in LAYOUT_DIRS:
            if layout.startswith(layout_dir):
                relative_path = os.path.relpath(layout, start=layout_dir)
                name = relative_path.replace(".jsonc", "")
                style_path = resolve_style_path(layout)
                layout_style_pairs.append(
                    {"layout": layout, "name": name, "style": style_path}
                )
                break

    return {"layouts": layout_style_pairs}


def list_layouts_json():
    """List all layouts in JSON format with their matching styles."""
    layouts_json = json.dumps(list_layouts(), indent=4)
    print(layouts_json)
    sys.exit(0)


def list_layouts_json_text():
    return json.dumps(list_layouts(), indent=4)


def synchronize_layout_state(skip_layout_sync=False):
    if skip_layout_sync:
        logger.debug("Skipping layout sync for CSS-only action")
        return

    logger.debug(f"Looking for state file at: {STATE_FILE}")

    if STATE_FILE.exists():
        logger.debug(f"State file found: {STATE_FILE}")
        layout_path = get_state_value("WAYBAR_LAYOUT_PATH")

        if layout_path and os.path.exists(layout_path):
            if not CONFIG_JSONC.exists():
                logger.debug("Config file missing, creating from layout path")
                CONFIG_JSONC.parent.mkdir(parents=True, exist_ok=True)
                atomic_copy_file(layout_path, CONFIG_JSONC)
                logger.debug("Created config.jsonc from state file layout")
            else:
                config_hash = get_file_hash(CONFIG_JSONC)
                layout_hash = get_file_hash(layout_path)
                if config_hash != layout_hash:
                    logger.debug("Config hash differs from layout hash, updating config")
                    try:
                        atomic_copy_file(layout_path, CONFIG_JSONC)
                        logger.debug("Updated config.jsonc with layout from state file")
                    except Exception as exc:
                        logger.error(f"Failed to update config.jsonc: {exc}")

        elif layout_path and not os.path.exists(layout_path):
            logger.warning(f"Layout path in state file doesn't exist: {layout_path}")
            layout_name = get_state_value("WAYBAR_LAYOUT_NAME")
            if layout_name:
                logger.debug(f"Looking for layout by name: {layout_name}")
                layouts = find_layout_files()
                found_layout = None
                for layout in layouts:
                    if os.path.basename(layout).replace(".jsonc", "") == layout_name:
                        logger.debug(f"Found layout by name: {layout}")
                        found_layout = layout
                        break

                if found_layout:
                    set_state_values({"WAYBAR_LAYOUT_PATH": found_layout})
                    CONFIG_JSONC.parent.mkdir(parents=True, exist_ok=True)

                    if CONFIG_JSONC.exists():
                        config_hash = get_file_hash(CONFIG_JSONC)
                        layout_hash = get_file_hash(found_layout)
                        if config_hash != layout_hash:
                            logger.debug("Config hash differs from layout hash, updating config")
                            atomic_copy_file(found_layout, CONFIG_JSONC)
                            logger.debug("Updated config.jsonc with layout by name")
                    else:
                        atomic_copy_file(found_layout, CONFIG_JSONC)
                        logger.debug("Created config.jsonc from layout by name")
                else:
                    logger.error(f"Could not find layout by name: {layout_name}")
                    layouts = find_layout_files()
                    if layouts:
                        first_layout = layouts[0]
                        first_layout_name = os.path.basename(first_layout).replace(".jsonc", "")
                        set_state_values(
                            {
                                "WAYBAR_LAYOUT_PATH": first_layout,
                                "WAYBAR_LAYOUT_NAME": first_layout_name,
                            }
                        )
                        CONFIG_JSONC.parent.mkdir(parents=True, exist_ok=True)
                        atomic_copy_file(first_layout, CONFIG_JSONC)
                        logger.debug(f"Used first available layout: {first_layout}")
        else:
            logger.debug("No valid layout path in state file, determining current layout")
            current_layout = get_current_layout_from_config()
            if current_layout:
                CONFIG_JSONC.parent.mkdir(parents=True, exist_ok=True)
                atomic_copy_file(current_layout, CONFIG_JSONC)
                logger.debug(f"Created config.jsonc from determined layout: {current_layout}")
    else:
        logger.debug("State file not found, creating it")
        ensure_state_file()
