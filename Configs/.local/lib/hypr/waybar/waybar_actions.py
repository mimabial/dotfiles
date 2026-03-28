#!/usr/bin/env python3
import glob
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyutils.compositor as HYPRLAND
import pyutils.wrapper.libnotify as notify
from pyutils.wrapper.rofi import rofi_dmenu
from pyutils.xdg_base_dirs import xdg_config_home
from waybar_assets import refresh_waybar_assets, write_style_file
from waybar_runtime import (
    restart_waybar,
    sync_dunst_position,
    sync_dunst_position_after_waybar_restart,
)
from waybar_shared import CONFIG_JSONC, atomic_copy_file, logger
from waybar_state import (
    get_current_layout_from_config,
    get_state_value,
    list_layouts,
    resolve_rofi_theme,
    resolve_style_path,
    set_state_values,
)


def rofi_file_selector(
    dirs,
    extension,
    prompt,
    current_selection=None,
    extra_flags=None,
    display_func=None,
    recursive=True,
):
    """Generic rofi file selector for files in given dirs with given extension."""
    files = []
    file_roots = []
    for directory in reversed(dirs):
        if recursive:
            found = [
                file_path
                for file_path in glob.glob(
                    os.path.join(directory, f"**/*{extension}"), recursive=True
                )
                if "/backup/" not in file_path and "\\backup\\" not in file_path
            ]
        else:
            found = [
                file_path
                for file_path in glob.glob(
                    os.path.join(directory, f"*{extension}"), recursive=False
                )
                if "/backup/" not in file_path and "\\backup\\" not in file_path
            ]
        files.extend(found)
        file_roots.extend([directory] * len(found))

    layered = {}
    for file_path, root_dir in zip(files, file_roots):
        try:
            key = os.path.relpath(file_path, start=root_dir)
        except ValueError:
            key = os.path.basename(file_path)
        layered[key] = (file_path, root_dir)

    files = []
    file_roots = []
    for key in sorted(layered):
        file_path, root_dir = layered[key]
        files.append(file_path)
        file_roots.append(root_dir)

    if not files:
        logger.error(f"No files found for extension {extension} in {dirs}")
        return None

    if display_func:
        names = [display_func(file_path, root_dir) for file_path, root_dir in zip(files, file_roots)]
    else:
        names = [os.path.splitext(os.path.basename(file_path))[0] for file_path in files]

    if current_selection:
        if display_func:
            current_name = None
            for file_path, root_dir in zip(files, file_roots):
                if os.path.abspath(file_path) == os.path.abspath(current_selection):
                    current_name = display_func(file_path, root_dir)
                    break
            if not current_name:
                current_name = names[0]
        else:
            current_name = os.path.splitext(os.path.basename(current_selection))[0]
    else:
        current_name = names[0]

    hyprland = HYPRLAND.HyprctlWrapper()
    try:
        override_string = hyprland.get_rofi_override_string()
        rofi_pos_string = hyprland.get_rofi_pos()
        rofi_flags = [
            "-p",
            prompt,
            "-select",
            current_name,
            "-theme",
            resolve_rofi_theme("clipboard"),
            "-theme-str",
            override_string,
            "-theme-str",
            rofi_pos_string,
        ]
    except (OSError, EnvironmentError):
        rofi_flags = [
            "-p",
            prompt,
            "-select",
            current_name,
            "-theme",
            resolve_rofi_theme("clipboard"),
        ]
    if extra_flags:
        rofi_flags.extend(extra_flags)

    selected = rofi_dmenu(names, rofi_flags)
    logger.debug(f"Selected {prompt}: {selected}")
    if selected:
        for file_path, name in zip(files, names):
            if name == selected:
                return file_path
    return None


def commit_user_waybar_change(
    *,
    layout_path=None,
    layout_name=None,
    style_path=None,
    notification_body=None,
    replace_id=None,
    transient=False,
    sync_tag=None,
):
    """Apply a user-requested layout/style change and let one restart path own the commit."""
    style_filepath = os.path.join(str(xdg_config_home()), "waybar", "style.css")
    state_updates = {}

    if layout_path is not None:
        state_updates["WAYBAR_LAYOUT_PATH"] = layout_path
        if layout_name is not None:
            state_updates["WAYBAR_LAYOUT_NAME"] = layout_name
        atomic_copy_file(layout_path, CONFIG_JSONC)

    if style_path is not None:
        state_updates["WAYBAR_STYLE_PATH"] = style_path
        write_style_file(style_filepath, style_path)

    if state_updates:
        set_state_values(state_updates)

    refresh_waybar_assets()
    sync_dunst_position("--write-only")
    restart_waybar()
    sync_dunst_position_after_waybar_restart()
    if notification_body:
        notify.send(
            "Waybar",
            notification_body,
            expire_time=2000,
            icon="preferences-desktop-display",
            replace_id=replace_id,
            transient=transient,
            sync_tag=sync_tag,
        )


def set_layout(layout):
    """Set the layout and corresponding style."""
    layouts_data = list_layouts()
    layout_path = None
    layout_name = None
    style_path = None

    for pair in layouts_data["layouts"]:
        if layout == pair["layout"] or layout == pair["name"]:
            layout_path = pair["layout"]
            layout_name = pair["name"]
            style_path = pair["style"]
            break

    if not layout_path:
        logger.error(f"Layout {layout} not found")
        sys.exit(1)

    commit_user_waybar_change(
        layout_path=layout_path,
        layout_name=layout_name,
        style_path=style_path,
        notification_body=f"Layout changed to {layout}",
        replace_id=91,
        transient=True,
        sync_tag="hypr-waybar-layout",
    )


def handle_layout_navigation(option, argv=None):
    """Handle --next, --prev, and --set options."""
    argv = list(sys.argv[1:] if argv is None else argv)
    layouts_data = list_layouts()
    layout_list = [layout["layout"] for layout in layouts_data["layouts"]]
    current_layout = get_state_value("WAYBAR_LAYOUT_PATH")

    if not current_layout:
        logger.error("Current layout not found in state file.")
        return

    if current_layout not in layout_list:
        logger.warning("Current layout file not found, re-caching layouts.")
        current_layout = get_current_layout_from_config()
        if not current_layout:
            logger.error("Failed to recache current layout.")
            return

    current_index = layout_list.index(current_layout)
    if option == "--next":
        next_index = (current_index + 1) % len(layout_list)
        set_layout(layout_list[next_index])
    elif option == "--prev":
        prev_index = (current_index - 1 + len(layout_list)) % len(layout_list)
        set_layout(layout_list[prev_index])
    elif option == "--set":
        if len(argv) >= 2 and argv[0] == "--set":
            set_layout(argv[1])
            return
        if len(argv) >= 3 and argv[1] == "--set":
            set_layout(argv[2])
            return
        if len(argv) >= 2 and argv[0] in {"-s", "--set"}:
            set_layout(argv[1])
            return
        if len(argv) >= 3 and argv[1] in {"-s", "--set"}:
            set_layout(argv[2])
            return
        if len(argv) < 2:
            logger.error("Usage: --set <layout>")
            return
        logger.error(f"Could not resolve layout from arguments: {argv}")


def style_selector():
    """Show all styles in rofi and apply the selected one."""
    current_style_path = get_state_value("WAYBAR_STYLE_PATH")
    selected_style = rofi_file_selector(
        STYLE_DIRS, ".css", "Select style:", current_style_path, recursive=False
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
    layouts_data = list_layouts()
    current_layout_path = get_state_value("WAYBAR_LAYOUT_PATH")

    def display_func(file_path, root_dir):
        rel = os.path.relpath(file_path, root_dir) if root_dir else os.path.basename(file_path)
        return rel.replace(".jsonc", "")

    selected_layout = rofi_file_selector(
        LAYOUT_DIRS,
        ".jsonc",
        "Select layout:",
        current_layout_path,
        display_func=display_func,
        extra_flags=["-theme-str", 'entry {placeholder: "󰍜  Waybar Layout";}'],
    )
    if selected_layout:
        for pair in layouts_data["layouts"]:
            if pair["layout"] == selected_layout:
                style_path = pair["style"]
                break
        else:
            style_path = resolve_style_path(selected_layout)
        commit_user_waybar_change(
            layout_path=selected_layout,
            layout_name=os.path.basename(selected_layout).replace(".jsonc", ""),
            style_path=style_path,
            notification_body=f"Layout changed to {display_func(selected_layout, os.path.dirname(selected_layout))}",
            replace_id=9,
        )
    return selected_layout


def select_layout_and_style():
    """Select layout, then style."""
    selected_layout = layout_selector()
    if selected_layout:
        style_selector()
    sys.exit(0)
