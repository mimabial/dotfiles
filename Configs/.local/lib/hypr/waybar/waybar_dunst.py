#!/usr/bin/env python3
"""Dunst position synchronization driven by Waybar.

When Waybar's position changes, Dunst's notification origin/offset must move
so notifications don't appear underneath the bar. The actual Dunst write is
done by `wal/wal.dunst.sh` (which reads Waybar's config.jsonc); this module
shells out to it after Waybar restarts.

This is a cross-subsystem coupling: Waybar reaches into wal/dunst territory.
The reverse coupling (wal.dunst.sh reading Waybar's config) lives there.
Documented here so a maintainer adjusting either side knows where the
other half lives.
"""
import json
import os
import subprocess
import time

from waybar_shared import CONFIG_JSONC, DUNST_SYNC_SCRIPT, logger


def sync_dunst_position(mode=None):
    """Invoke wal.dunst.sh to update Dunst's origin/offset based on the
    current Waybar position. `mode` is forwarded as the script's argv[1]
    (typically "--write-only" or "--reload-only"); None lets the script
    pick its default ("write-and-reload")."""
    if not os.path.exists(DUNST_SYNC_SCRIPT):
        return

    cmd = [DUNST_SYNC_SCRIPT]
    if mode:
        cmd.append(mode)
    try:
        subprocess.run(cmd, timeout=5, check=False)
        logger.debug(
            f"Synced dunst position with waybar ({mode or 'write-and-reload'})"
        )
    except Exception as exc:
        logger.warning(f"Failed to sync dunst position: {exc}")


def get_waybar_position():
    """Read Waybar's `position` from CONFIG_JSONC (top|bottom|left|right)."""
    try:
        with open(CONFIG_JSONC, "r") as file:
            return json.load(file).get("position", "right")
    except Exception:
        return "right"


def read_focused_monitor_reserved():
    """Return the focused monitor's reserved-edge tuple [left, top, right,
    bottom] from hyprctl, or None if unavailable."""
    try:
        result = subprocess.run(
            ["hyprctl", "monitors", "-j"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        monitors = json.loads(result.stdout)
        if not monitors:
            return None
        monitor = next((item for item in monitors if item.get("focused")), monitors[0])
        reserved = monitor.get("reserved")
        if isinstance(reserved, list) and len(reserved) == 4:
            return reserved
    except Exception as exc:
        logger.debug(f"Failed to read monitor reserved edges: {exc}")
    return None


def wait_for_waybar_reserved_edge(position, timeout=2.0):
    """Block until the focused monitor reports a non-zero reserved edge in
    the direction Waybar lives, or `timeout` seconds elapse. Used post-restart
    so Dunst is updated only after Waybar has actually claimed its space."""
    edge_index = {"left": 0, "top": 1, "right": 2, "bottom": 3}.get(position)
    if edge_index is None:
        return False

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        reserved = read_focused_monitor_reserved()
        if reserved and reserved[edge_index] > 0:
            return True
        time.sleep(0.05)
    return False


def sync_dunst_position_after_waybar_restart():
    """Wait for Waybar to claim its monitor edge, then trigger the Dunst
    reload. Called from the apply path right after restart_waybar() so the
    user never sees notifications stranded behind the bar's old geometry."""
    wait_for_waybar_reserved_edge(get_waybar_position())
    sync_dunst_position("--reload-only")
