from pathlib import Path

from pyutils.xdg_base_dirs import xdg_runtime_dir

LOCK_NAMES = {
    "color_gen": "color-gen.lock",
    "color_cache_only": "color-cache-only.lock",
    "theme_update": "theme-update.lock",
    "theme_update_meta": "theme-update.meta",
    "theme_switch": "theme-switch.lock",
    "theme_precache": "theme-precache.lock",
    "theme_phase_d_gtk": "theme-phase-d-gtk.lock",
    "theme_phase_d_qt": "theme-phase-d-qt.lock",
    "theme_phase_d_chrome": "theme-phase-d-chrome.lock",
    "theme_phase_d_firefox": "theme-phase-d-firefox.lock",
    "theme_phase_d_gimp": "theme-phase-d-gimp.lock",
    "theme_phase_d_theme_files": "theme-phase-d-theme-files.lock",
    "theme_phase_d_desktop": "theme-phase-d-desktop.lock",
    "waybar": "waybar.lock",
    "waybar_op": "waybar-op.lock",
    "waybar_watch": "waybar-watch.lock",
    "waybar_watch_meta": "waybar-watch.meta",
    "wallpaper_cache": "wallpaper-cache.lock",
    "wallpaper_inventory": "wallpaper-inventory.lock",
    "wallpaper_switch": "wallpaper-switch.lock",
    "wallpaper_awww": "wallpaper-awww.lock",
    "mode_switch": "mode-switch.lock",
    "wal_cache_clean": "wal-cache-clean.lock",
    "wal_cache_store": "wal-cache-store.lock",
    "wal_cache_prune": "wal-cache-prune.lock",
}


def runtime_lock_name(name: str) -> str:
    return LOCK_NAMES[name]


def runtime_lock_path(name: str) -> Path:
    return Path(xdg_runtime_dir()) / runtime_lock_name(name)
