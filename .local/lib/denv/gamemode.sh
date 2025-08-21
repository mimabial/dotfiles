#!/usr/bin/env bash

GAMEMODE_STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/denv/gamemoderc"

is_gamemode_active() {
    [ -f "$GAMEMODE_STATE_FILE" ]
}

enable_gamemode() {
    mkdir -p "$(dirname "$GAMEMODE_STATE_FILE")"
    
    hyprctl -q --batch "\
        keyword animations:enabled 0;\
        keyword decoration:shadow:enabled 0;\
        keyword decoration:blur:xray 1;\
        keyword decoration:blur:enabled 0;\
        keyword general:gaps_in 0;\
        keyword general:gaps_out 0;\
        keyword general:border_size 1;\
        keyword decoration:rounding 0;\
        keyword decoration:active_opacity 1;\
        keyword decoration:inactive_opacity 1;\
        keyword decoration:fullscreen_opacity 1;\
        keyword layerrule noanim,waybar;\
        keyword layerrule noanim,swaync-notification-window;\
        keyword layerrule noanim,swww-daemon;\
        keyword layerrule noanim,rofi"
    
    hyprctl keyword windowrule "opaque,class:(.*)"
    touch "$GAMEMODE_STATE_FILE"
    pkill -RTMIN+10 waybar 2>/dev/null || true
    notify-send -i "applications-games" "Gamemode" "Performance mode enabled" 2>/dev/null || true
}

disable_gamemode() {
    hyprctl reload config-only -q
    rm -f "$GAMEMODE_STATE_FILE"
    pkill -RTMIN+10 waybar 2>/dev/null || true
    notify-send -i "applications-games" "Gamemode" "Normal mode restored" 2>/dev/null || true
}

toggle_gamemode() {
    if is_gamemode_active; then
        disable_gamemode
    else
        enable_gamemode
    fi
}

show_status() {
    if is_gamemode_active; then
        echo "Gamemode: ACTIVE"
        return 0
    else
        echo "Gamemode: INACTIVE"
        return 1
    fi
}

waybar_output() {
    if is_gamemode_active; then
        echo '{"text": " ", "tooltip": "Gamemode: ACTIVE\nPerformance mode enabled", "class": "gamemode-active"}'
    else
        echo '{"text": " ", "tooltip": "Gamemode: INACTIVE\nClick to enable performance mode", "class": "gamemode-inactive"}'
    fi
}

case "${1:-toggle}" in
    "on"|"enable"|"1")
        if ! is_gamemode_active; then
            enable_gamemode
        else
            echo "Gamemode is already active"
        fi
        ;;
    "off"|"disable"|"0")
        if is_gamemode_active; then
            disable_gamemode
        else
            echo "Gamemode is already inactive"
        fi
        ;;
    "toggle"|"")
        toggle_gamemode
        ;;
    "status"|"check")
        show_status
        ;;
    "waybar"|"json")
        waybar_output
        ;;
    "help"|"-h"|"--help")
        cat << EOF
Usage: $0 [COMMAND]

Commands:
    on, enable, 1     Enable gamemode
    off, disable, 0   Disable gamemode  
    toggle            Toggle gamemode (default)
    status, check     Show current status
    waybar, json      Output JSON for waybar
    help              Show this help

Examples:
    $0                # Toggle gamemode
    $0 on             # Enable gamemode
    $0 off            # Disable gamemode
    $0 status         # Check if gamemode is active
    $0 waybar         # Output waybar JSON
EOF
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
