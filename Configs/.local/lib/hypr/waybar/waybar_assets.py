#!/usr/bin/env python3
import glob
import json
import os
import re
import sys

from pyutils.xdg_base_dirs import xdg_config_home, xdg_data_home

from waybar_shared import (
    CONFIG_JSONC,
    CONFIG_WAYBAR_DIR,
    DATA_WAYBAR_DIR,
    INCLUDES_DIRS,
    MODULE_DIRS,
    atomic_copy_file,
    atomic_write_json,
    atomic_write_text,
    ensure_directory_exists,
    logger,
)
from pyutils.compositor import HyprctlWrapper
from waybar_state import (
    get_config_value,
    get_current_layout_from_config,
    resolve_style_path,
)


def normalize_menu_file_path(raw_path):
    """Prefer user menu overrides, then shared stock menus."""
    if not isinstance(raw_path, str) or not raw_path:
        return raw_path

    menu_name = os.path.basename(raw_path)
    config_menu = CONFIG_WAYBAR_DIR / "menus" / menu_name
    if config_menu.is_file():
        return f"$XDG_CONFIG_HOME/waybar/menus/{menu_name}"

    shared_menu = DATA_WAYBAR_DIR / "menus" / menu_name
    if shared_menu.is_file():
        return f"$XDG_DATA_HOME/waybar/menus/{menu_name}"

    return raw_path


def rewrite_module_paths(data):
    """Normalize layered file references inside module definitions."""
    if isinstance(data, dict):
        for key, value in data.items():
            if key == "menu-file":
                data[key] = normalize_menu_file_path(value)
            elif isinstance(value, (dict, list)):
                rewrite_module_paths(value)
    elif isinstance(data, list):
        for item in data:
            rewrite_module_paths(item)
    return data


def normalize_jsonc(content):
    """Convert JSONC content to strict JSON by removing comments and trailing commas."""
    no_comments = []
    in_string = False
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = 0
    length = len(content)

    while i < length:
        char = content[i]
        next_char = content[i + 1] if i + 1 < length else ""

        if in_line_comment:
            if char == "\n":
                in_line_comment = False
                no_comments.append(char)
            i += 1
            continue

        if in_block_comment:
            if char == "*" and next_char == "/":
                in_block_comment = False
                i += 2
                continue
            if char == "\n":
                no_comments.append(char)
            i += 1
            continue

        if in_string:
            no_comments.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
            continue

        if char == '"':
            in_string = True
            no_comments.append(char)
            i += 1
            continue

        if char == "/" and next_char == "/":
            in_line_comment = True
            i += 2
            continue

        if char == "/" and next_char == "*":
            in_block_comment = True
            i += 2
            continue

        no_comments.append(char)
        i += 1

    cleaned = "".join(no_comments)

    result = []
    in_string = False
    escaped = False
    i = 0
    length = len(cleaned)

    while i < length:
        char = cleaned[i]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
            continue

        if char == '"':
            in_string = True
            result.append(char)
            i += 1
            continue

        if char == ",":
            j = i + 1
            while j < length and cleaned[j].isspace():
                j += 1
            if j < length and cleaned[j] in "}]":
                i += 1
                continue

        result.append(char)
        i += 1

    return "".join(result)


def parse_json_file(filepath):
    """Parse a JSON file and return the data."""
    with open(filepath, "r", encoding="utf-8") as file:
        content = file.read()
    if os.fspath(filepath).endswith(".jsonc"):
        content = normalize_jsonc(content)
    return json.loads(content)


def modify_json_key(data, key, value):
    """Recursively modify the specified key with the given value in the JSON data."""
    if isinstance(data, dict):
        for k, v in data.items():
            if k == key:
                data[k] = value
            elif isinstance(v, dict):
                modify_json_key(v, key, value)
            elif isinstance(v, list):
                for item in v:
                    if isinstance(item, dict):
                        modify_json_key(item, key, value)
    return data


def write_style_file(style_filepath, source_filepath):
    """Override the style file with the given source style."""
    config_root = os.path.join(str(xdg_config_home()), "waybar")
    style_import = os.path.relpath(os.path.abspath(source_filepath), start=config_root)

    style_css = f"""
    /*!  DO NOT EDIT THIS FILE */

    /* Modify/add style in ~/.config/waybar/styles/ */
    @import "includes/global.css";
    @import "includes/font.css";
    @import "includes/border-radius.css";

    /* Colors configuration is generated through pywal16 in the `colors.css` file */
    @import "colors.css";

    /* Theme configuration is generated through the `theme.css` file */
    @import "theme.css";

    /* Shared or user-selected base style */
    @import "{style_import}";

    /* Users override the current style here */
    @import "user-style.css";
    """
    atomic_write_text(style_filepath, style_css)
    logger.debug(f"Successfully wrote style to '{style_filepath}'")


def update_icon_size():
    includes_file = os.path.join(str(xdg_config_home()), "waybar", "includes", "includes.json")

    ensure_directory_exists(includes_file)

    if os.path.exists(includes_file):
        try:
            with open(includes_file, "r") as file:
                existing_data = json.load(file)
        except (json.JSONDecodeError, FileNotFoundError):
            existing_data = {"include": []}
    else:
        existing_data = {"include": []}

    includes_data = {"include": existing_data.get("include", [])}
    if "position" in existing_data:
        includes_data["position"] = existing_data["position"]

    icon_size = get_waybar_icon_size()
    updated_entries = {}

    for directory in reversed(MODULE_DIRS):
        for pattern in ("*.json", "*.jsonc"):
            for json_file in glob.glob(os.path.join(directory, pattern)):
                data = parse_json_file(json_file)

                for key, value in data.items():
                    if isinstance(value, dict):
                        icon_size_multiplier = value.get("icon-size-multiplier", 1)
                        final_icon_size = int(icon_size * icon_size_multiplier)
                        data[key] = modify_json_key(value, "icon-size", final_icon_size)
                        data[key] = modify_json_key(value, "tooltip-icon-size", final_icon_size)
                        data[key] = modify_json_key(value, "size", final_icon_size)

                data = rewrite_module_paths(data)
                updated_entries.update(data)

    includes_data.update(updated_entries)
    atomic_write_json(includes_file, includes_data)
    logger.debug(
        f"Successfully updated icon sizes and appended to '{includes_file}' with {len(updated_entries)} entries."
    )


def update_global_css():
    """Generate dynamic global.css with font family and size based on theme and state file."""
    global_css_path = os.path.join(str(xdg_config_home()), "waybar", "includes", "global.css")
    logger.debug(f"Updating global CSS in {global_css_path}")

    ensure_directory_exists(global_css_path)
    font_size = get_waybar_font_size()
    logger.debug(f"Final font size: {font_size}")

    global_css_content = f"""/*
 Dynamic Style Configuration *
 This is handled by System

 To generate a dynamic configuration 
 base on theme and user settings

*/

* {{
    border-radius: 0em;
    font-size: {font_size}px;
}}
"""

    atomic_write_text(global_css_path, global_css_content)
    logger.debug(f"Successfully generated global CSS at '{global_css_path}'")


def get_waybar_value_from_sources(value_name, default_value, sources):
    def _try_parse_value(raw_value, source_name):
        if type(default_value) is str:
            return _try_parse_str_value(raw_value, source_name)
        if type(default_value) is int:
            return _try_parse_int_value(raw_value, source_name)
        return None

    def _try_parse_str_value(raw_value, source_name):
        if not raw_value:
            return None
        sanitized_value = raw_value.strip().strip('"').strip("'")
        if not sanitized_value:
            logger.warning(f"Invalid empty {value_name} from {source_name}")
            return None
        logger.debug(f"Got {value_name} from {source_name}: {sanitized_value}")
        return sanitized_value

    def _try_parse_int_value(raw_value, source_name):
        if not raw_value:
            return None
        try:
            int_value = int(raw_value)
            logger.debug(f"Got {value_name} from {source_name}: {int_value}")
            return int_value
        except ValueError:
            logger.warning(f"Invalid {value_name} from {source_name}: {raw_value}")
            return None

    for get_source_func, source_name in sources:
        raw_value = get_source_func()
        parsed_value = _try_parse_value(raw_value, source_name)
        if parsed_value is not None:
            return parsed_value

    logger.debug(f"Using default {value_name}: {default_value}")
    return default_value


def get_waybar_font_family():
    font_family_sources = [
        (lambda: get_value_from_hypr_config("$BAR_FONT"), "BAR_FONT config"),
        (lambda: get_value_from_hypr_config("$FONT"), "FONT config"),
    ]
    return get_waybar_value_from_sources("font family", "monospace", font_family_sources)


def get_waybar_font_size():
    font_size_sources = [
        (lambda: get_config_value("WAYBAR_SCALE"), "WAYBAR_SCALE config"),
        (lambda: get_value_from_hypr_config("$BAR_FONT_SIZE"), "BAR_FONT_SIZE config"),
        (lambda: get_value_from_hypr_config("$FONT_SIZE"), "FONT_SIZE config"),
    ]
    return get_waybar_value_from_sources("font size", 10, font_size_sources)


def get_waybar_icon_size():
    icon_sources = [
        (lambda: get_config_value("WAYBAR_ICON_SIZE"), "WAYBAR_ICON_SIZE config"),
        (lambda: get_config_value("WAYBAR_SCALE"), "WAYBAR_SCALE config"),
    ]
    return get_waybar_value_from_sources("icon size", 10, icon_sources)


def get_value_from_hypr_config(variable_name):
    """Read a Hypr variable from live theme metadata, then persistent font/default files."""
    variable_key = variable_name.lstrip("$")
    config_home = xdg_config_home()
    candidate_files = [
        config_home / "hypr" / "themes" / "theme.conf",
        config_home / "hypr" / "userfonts.conf",
        xdg_data_home() / "hypr" / "variables.conf",
    ]

    for file_path in candidate_files:
        if not file_path.exists():
            continue
        try:
            with open(file_path, "r") as file:
                for line in file:
                    stripped = line.strip()
                    if not stripped or stripped.startswith("#") or "=" not in stripped:
                        continue
                    lhs, rhs = stripped.split("=", 1)
                    if lhs.strip() != f"${variable_key}":
                        continue
                    value = rhs.strip().strip('"').strip("'")
                    if not value:
                        logger.warning(f"Invalid empty {variable_name} in {file_path}")
                        return None
                    logger.debug(f"Got {variable_name} from {file_path}: {value}")
                    return value or None
        except Exception as e:
            logger.error(f"Error reading {file_path}: {e}")

    logger.debug(f"{variable_name} not found in Hypr config files")
    return None


def update_border_radius():
    css_filepath = os.path.join(str(xdg_config_home()), "waybar", "includes", "border-radius.css")
    logger.debug(f"Updating border radius in {css_filepath}")

    ensure_directory_exists(css_filepath)
    logger.debug("Directory for border-radius.css ensured")

    if not os.path.exists(css_filepath):
        for includes_dir in INCLUDES_DIRS:
            template_path = os.path.join(includes_dir, "border-radius.css")
            if os.path.exists(template_path):
                logger.debug(f"Found template at {template_path}, copying to {css_filepath}")
                atomic_copy_file(template_path, css_filepath)
                break
        else:
            default_template = "/*\nThis file is autogenerated.\n*/\n\n* {\n  border-radius: 0pt;\n}\n"
            atomic_write_text(css_filepath, default_template)
            logger.debug("Wrote default border-radius.css template")

    border_radius = os.getenv("WAYBAR_BORDER_RADIUS")
    logger.debug(f"WAYBAR_BORDER_RADIUS env: {border_radius}")

    if not border_radius:
        border_radius = os.getenv("hypr_border")
        logger.debug(f"hypr_border env: {border_radius}")

    if not border_radius:
        logger.debug("Reading border radius from Hyprland")
        try:
            border_radius = HyprctlWrapper.getoption("decoration:rounding")
            logger.debug(f"Got border radius from Hyprland: {border_radius}")
        except (EnvironmentError, RuntimeError, ValueError) as e:
            logger.warning(f"Failed to read border radius from Hyprland: {e}")

    try:
        border_radius = int(str(border_radius).strip())
    except (TypeError, ValueError):
        logger.warning(f"Invalid border radius {border_radius!r}; using default")
        border_radius = 2

    if border_radius < 0:
        logger.warning(f"Invalid negative border radius {border_radius!r}; using default")
        border_radius = 2
        logger.debug(f"Using default border radius: {border_radius}")

    logger.debug(f"Final border radius value: {border_radius}")

    with open(css_filepath, "r") as file:
        content = file.read()
    logger.debug(f"Read {len(content)} bytes from {css_filepath}")

    updated_content = re.sub(r"\d+pt", f"{border_radius}pt", content)
    logger.debug("Applied border radius value to CSS content")

    if updated_content == content:
        logger.debug("Border radius unchanged; skipping write")
        return

    atomic_write_text(css_filepath, updated_content)
    logger.debug(f"Successfully updated border radius in {css_filepath}")


def generate_includes():
    includes_file = os.path.join(str(xdg_config_home()), "waybar", "includes", "includes.json")
    ensure_directory_exists(includes_file)

    if os.path.exists(includes_file):
        with open(includes_file, "r") as file:
            includes_data = json.load(file)
    else:
        includes_data = {"include": []}

    includes = {}
    for directory in reversed(MODULE_DIRS):
        if not os.path.isdir(directory):
            logger.debug(f"Directory '{directory}' does not exist, skipping...")
            continue
        for pattern in ("*.json", "*.jsonc"):
            for path in glob.glob(os.path.join(directory, pattern)):
                relative_path = os.path.relpath(path, start=directory)
                includes[relative_path] = path

    config_root = str(xdg_config_home())
    data_root = str(xdg_data_home())

    def normalize_include_path(path):
        if path.startswith(config_root + os.sep):
            return path.replace(config_root, "$XDG_CONFIG_HOME", 1)
        if path.startswith(data_root + os.sep):
            return path.replace(data_root, "$XDG_DATA_HOME", 1)
        return path

    includes_data["include"] = [normalize_include_path(includes[key]) for key in sorted(includes)]

    position = get_config_value("WAYBAR_POSITION")
    if position:
        position = position.strip().strip('"').strip("'")
    else:
        position = "top"
    includes_data["position"] = position

    atomic_write_json(includes_file, includes_data)
    logger.debug(
        f"Successfully updated '{includes_file}' with {len(includes_data['include'])} entries and position '{position}'."
    )


def update_config(config_path):
    config_jsonc = os.path.join(str(xdg_config_home()), "waybar", "config.jsonc")
    atomic_copy_file(config_path, config_jsonc)
    logger.debug(f"Successfully copied config from '{config_path}' to '{config_jsonc}'")


def update_style(style_path=None):
    style_filepath = os.path.join(str(xdg_config_home()), "waybar", "style.css")
    user_style_filepath = os.path.join(str(xdg_config_home()), "waybar", "user-style.css")
    theme_style_filepath = os.path.join(str(xdg_config_home()), "waybar", "theme.css")

    ensure_directory_exists(user_style_filepath)

    if not os.path.exists(user_style_filepath):
        atomic_write_text(user_style_filepath, "/* User custom styles */\n")
        logger.debug(f"Created '{user_style_filepath}'")

    if not os.path.exists(theme_style_filepath):
        logger.error(f"Missing '{theme_style_filepath}', Please run 'hyprshell reload' to generate it.")

    if not style_path:
        current_layout = get_current_layout_from_config()
        logger.debug(f"Detected current layout: '{current_layout}'")
        if not current_layout:
            logger.error("Failed to get current layout from config.")
            sys.exit(1)
        style_path = resolve_style_path(current_layout)
    if not os.path.exists(style_path):
        logger.error(f"Cannot reconcile style path: {style_path}")
        sys.exit(1)
    write_style_file(style_filepath, style_path)


def refresh_waybar_assets():
    update_icon_size()
    update_border_radius()
    generate_includes()
    update_global_css()
