#!/usr/bin/env python3
import os
import sys

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
    resolve_style_path,
    set_state_values,
)

import pyutils.wrapper.libnotify as notify


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


def resolve_layout_entry(layout_reference):
    """Resolve a layout argument to its discovered layout/style pair."""
    for pair in list_layouts()["layouts"]:
        if layout_reference in {pair["layout"], pair["name"]}:
            return pair
    return None


def set_layout(layout):
    """Set the layout and corresponding style."""
    layout_entry = resolve_layout_entry(layout)
    if not layout_entry:
        logger.error(f"Layout {layout} not found")
        sys.exit(1)

    commit_user_waybar_change(
        layout_path=layout_entry["layout"],
        layout_name=layout_entry["name"],
        style_path=layout_entry["style"],
        notification_body=f"Layout changed to {layout}",
        replace_id=91,
        transient=True,
        sync_tag="hypr-waybar-layout",
    )


def resolve_set_layout_argument(argv):
    """Resolve a --set or -s CLI argument to the requested layout reference."""
    for index, arg in enumerate(argv):
        if arg in {"--set", "-s"}:
            if index + 1 < len(argv):
                return argv[index + 1]
            logger.error("Usage: --set <layout>")
            return None
    logger.error(f"Could not resolve layout from arguments: {argv}")
    return None


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
        set_layout(layout_list[(current_index + 1) % len(layout_list)])
        return

    if option == "--prev":
        set_layout(layout_list[(current_index - 1 + len(layout_list)) % len(layout_list)])
        return

    if option == "--set":
        layout_reference = resolve_set_layout_argument(argv)
        if layout_reference:
            set_layout(layout_reference)
