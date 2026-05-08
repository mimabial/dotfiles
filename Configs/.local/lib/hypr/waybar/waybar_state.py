#!/usr/bin/env python3
import fcntl
import os
from contextlib import contextmanager

from waybar_layouts import find_layout_files
from waybar_shared import (
    CONFIG_JSONC,
    HYPR_ENV_OVERRIDES,
    STATE_FILE,
    atomic_write_text,
    get_active_config_layout_hash,
    get_file_hash,
    install_layout_as_active_config,
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


def get_state_value(key, default=None):
    """Get a value from the staterc.

    Sibling readers — they MUST agree on the file format described in
    waybar/STATE.md:
      - waybar.state.common.sh:waybar_state_value (Bash, used by indicator
        scripts; tolerates quotes and `export`)
      - waybar_watch.read_runtime_meta (Python, used for lock-meta files;
        strict KEY=value, no quoting)
    """
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

        install_layout_as_active_config(layout)
        logger.debug(f"Created config.jsonc with first layout: {layout}")
        return layout

    config_hash = get_active_config_layout_hash()
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
    install_layout_as_active_config(layout)
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
                install_layout_as_active_config(layout_path)
                logger.debug("Created config.jsonc from state file layout")
            else:
                config_hash = get_active_config_layout_hash()
                layout_hash = get_file_hash(layout_path)
                if config_hash != layout_hash:
                    logger.debug("Config hash differs from layout hash, updating config")
                    try:
                        install_layout_as_active_config(layout_path)
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
                        config_hash = get_active_config_layout_hash()
                        layout_hash = get_file_hash(found_layout)
                        if config_hash != layout_hash:
                            logger.debug("Config hash differs from layout hash, updating config")
                            install_layout_as_active_config(found_layout)
                            logger.debug("Updated config.jsonc with layout by name")
                    else:
                        install_layout_as_active_config(found_layout)
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
                        install_layout_as_active_config(first_layout)
                        logger.debug(f"Used first available layout: {first_layout}")
        else:
            logger.debug("No valid layout path in state file, determining current layout")
            current_layout = get_current_layout_from_config()
            if current_layout:
                CONFIG_JSONC.parent.mkdir(parents=True, exist_ok=True)
                install_layout_as_active_config(current_layout)
                logger.debug(f"Created config.jsonc from determined layout: {current_layout}")
    else:
        logger.debug("State file not found, creating it")
        ensure_state_file()
