#!/usr/bin/env python3
"""Layout / style / module file discovery for the waybar subsystem.

Pure filesystem walks across the layered XDG_CONFIG_HOME and XDG_DATA_HOME
trees. No state reads or writes. No process orchestration.

The layered directory model: user files in $XDG_CONFIG_HOME/waybar/<kind>/
override shared files in $XDG_DATA_HOME/waybar/<kind>/, which override stock
files in /usr/local/share/waybar/<kind>/ and /usr/share/waybar/<kind>/.
Last-override-wins by relative path.
"""
import glob
import json
import os

from waybar_shared import (
    CONFIG_ROFI_DIR,
    DATA_ROFI_DIR,
    LAYOUT_DIRS,
    LAYOUT_IGNORE,
    MODULE_DIRS,
    STYLE_DIRS,
    logger,
)


def find_layout_files():
    """Return all *.jsonc layout files across LAYOUT_DIRS, layered.

    User overrides win when the relative path matches; the first hit (from
    the highest-priority dir reached via reversed iteration) is kept."""
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


def layered_module_files():
    """Return the effective layered Waybar module files, last override wins."""
    modules = {}
    for directory in reversed(MODULE_DIRS):
        if not os.path.isdir(directory):
            logger.debug(f"Directory '{directory}' does not exist, skipping...")
            continue
        for pattern in ("*.json", "*.jsonc"):
            for path in glob.glob(os.path.join(directory, pattern)):
                relative_path = os.path.relpath(path, start=directory)
                modules[relative_path] = path
    return modules


def resolve_style_path(layout_path):
    """Resolve the style path matching a layout. Tries layout basename, then
    the part before any `#` suffix, then the parent directory name; falls
    back to defaults.css in the first STYLE_DIRS that has one."""
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


def list_layouts_json_text():
    """Return the layouts JSON as a string (no print, no exit)."""
    return json.dumps(list_layouts(), indent=4)
