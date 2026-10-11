#!/usr/bin/env bash

wallpaper_show_help() {
  cat <<EOT
Usage: hyprshell wallpaper <command> [options]
Set, rotate, cache and pick the desktop wallpaper.

Commands:
    json                      List wallpapers in JSON format
    select                    Select wallpaper using rofi
    next                      Set next wallpaper
    previous | prev           Set previous wallpaper
    random                    Set random wallpaper
    set <file>                Set a specific wallpaper
    start                     Apply the current wallpaper to the backend
    resume                    Reapply the current theme wallpaper
    display                   Display current wall.set without maintenance
    notify                    Show a notification for the current wallpaper
    get                       Print current wallpaper path
    output <file>             Copy current wallpaper to a file
    link                      Rebuild derived backend links from wall.set
    clean                     Remove cached thumbnails with no matching wallpapers

Options:
    -b, --backend <backend>   Set wallpaper backend to use (default: awww)
    -G, --global              Set wallpaper as global
        --wait-lock           Wait for the current wallpaper operation to finish
        --no-notify           Suppress wallpaper notifications for this run
    -t, --filetypes <types>   Override file types (colon-separated ':')
        --notify-body <text>  Override notification body
    -h, --help                Display this help message

Notes:
    .   --backend <backend> is also used to cache wallpapers/background images.
        Example: '--backend hyprlock' writes
        ~/.cache/hypr/wallpaper/current/hyprlock.png

    .   --global updates the theme wallpaper links and thumbnail cache.

    .   Interactive actions like next/previous/random/select wait for in-flight
        wallpaper operations by default.

    .   In select, Delete moves the highlighted wallpaper to Trash.

EOT
  exit 0
}
