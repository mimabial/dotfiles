#!/usr/bin/env python3
import glob
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyutils.compositor as HYPRLAND
from pyutils.wrapper.rofi import rofi_dmenu
from waybar_apply import commit_user_waybar_change, resolve_layout_entry
from waybar_layouts import resolve_rofi_theme, resolve_style_path
from waybar_shared import LAYOUT_DIRS, STYLE_DIRS, logger
from waybar_state import get_state_value


def _discover_layered_files(directories, extension, recursive):
    layered = {}
    pattern = f"**/*{extension}" if recursive else f"*{extension}"
    for directory in reversed(directories):
        for file_path in glob.glob(os.path.join(directory, pattern), recursive=recursive):
            if "/backup/" in file_path or "\\backup\\" in file_path:
                continue
            try:
                key = os.path.relpath(file_path, start=directory)
            except ValueError:
                key = os.path.basename(file_path)
            layered[key] = (file_path, directory)
    return [layered[key] for key in sorted(layered)]


def _resolve_current_selection_name(current_selection, files, names, display_func):
    if not current_selection:
        return names[0]

    if not display_func:
        return os.path.splitext(os.path.basename(current_selection))[0]

    for file_path, root_dir in files:
        if os.path.abspath(file_path) == os.path.abspath(current_selection):
            return display_func(file_path, root_dir)
    return names[0]


def _rofi_file_selector_flags(prompt, current_name, extra_flags):
    hyprland = HYPRLAND.HyprctlWrapper()
    base_flags = [
        "-p",
        prompt,
        "-select",
        current_name,
        "-theme",
        resolve_rofi_theme("clipboard"),
    ]
    try:
        base_flags.extend(
            [
                "-theme-str",
                hyprland.get_rofi_override_string(),
                "-theme-str",
                hyprland.get_rofi_pos(),
            ]
        )
    except (OSError, EnvironmentError):
        pass

    if extra_flags:
        base_flags.extend(extra_flags)
    return base_flags


def rofi_file_selector(
    directories,
    extension,
    prompt,
    current_selection=None,
    extra_flags=None,
    display_func=None,
    recursive=True,
):
    """Select a file from layered Waybar directories with a rofi menu."""
    files = _discover_layered_files(directories, extension, recursive)
    if not files:
        logger.error(f"No files found for extension {extension} in {directories}")
        return None

    if display_func:
        names = [display_func(file_path, root_dir) for file_path, root_dir in files]
    else:
        names = [os.path.splitext(os.path.basename(file_path))[0] for file_path, _ in files]

    current_name = _resolve_current_selection_name(
        current_selection,
        files,
        names,
        display_func,
    )
    rofi_flags = _rofi_file_selector_flags(prompt, current_name, extra_flags)

    selected = rofi_dmenu(names, rofi_flags)
    logger.debug(f"Selected {prompt}: {selected}")
    if not selected:
        return None

    for (file_path, _root_dir), name in zip(files, names):
        if name == selected:
            return file_path
    return None


def style_selector():
    """Show all styles in rofi and apply the selected one."""
    current_style_path = get_state_value("WAYBAR_STYLE_PATH")
    selected_style = rofi_file_selector(
        STYLE_DIRS,
        ".css",
        "Select style:",
        current_style_path,
        recursive=False,
    )
    if selected_style:
        commit_user_waybar_change(
            style_path=selected_style,
            notification_body=f"Style changed to {os.path.basename(selected_style)}",
            replace_id=9,
        )
    sys.exit(0)


def layout_selector():
    """Show all layouts in rofi and apply the selected one."""
    current_layout_path = get_state_value("WAYBAR_LAYOUT_PATH")

    def display_func(file_path, root_dir):
        relative_path = (
            os.path.relpath(file_path, root_dir)
            if root_dir
            else os.path.basename(file_path)
        )
        return relative_path.replace(".jsonc", "")

    selected_layout = rofi_file_selector(
        LAYOUT_DIRS,
        ".jsonc",
        "Select layout:",
        current_layout_path,
        display_func=display_func,
        extra_flags=[
            "-theme-str", 'entry {placeholder: "󰍜  Waybar Layout";}',
            "-theme-str", "window { width: 24em; }",
        ],
    )
    if selected_layout:
        layout_entry = resolve_layout_entry(selected_layout)
        if layout_entry is None:
            style_path = resolve_style_path(selected_layout)
            layout_name = os.path.basename(selected_layout).replace(".jsonc", "")
        else:
            style_path = layout_entry["style"]
            layout_name = layout_entry["name"]

        commit_user_waybar_change(
            layout_path=selected_layout,
            layout_name=layout_name,
            style_path=style_path,
            notification_body=(
                f"Layout changed to "
                f"{display_func(selected_layout, os.path.dirname(selected_layout))}"
            ),
            replace_id=9,
        )
    return selected_layout


def select_layout_and_style():
    """Select layout, then style."""
    selected_layout = layout_selector()
    if selected_layout:
        style_selector()
    sys.exit(0)
