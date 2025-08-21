#!/usr/bin/env bash

# shellcheck source=$HOME/.local/bin/denv-shell
# shellcheck disable=SC1091
if ! source "$(which denv-shell)"; then
    echo "[$0] :: Error: denv-shell not found."
    echo "[$0] :: Is DENv installed?"
    exit 1
fi

# Configuration paths and defaults
sunsetConf="${XDG_STATE_HOME:-$HOME/.local/state}/denv/hyprsunset"
default_temp=6500
default_gamma=100

# Get brightness information
get_brightness_info() {
    local brightness level icon
    brightness=$(brightnessctl -m | grep -o '[0-9]\+%' | head -c-2)
    level=$((brightness * 8 / 100))
    
    # Brightness icons array
    local icons=('󰃞' '󰃟' '󰃠' '󰃡' '󰃢' '󰃣' '󰃤' '󰃥' '󰃦')
    icon=${icons[$level]}
    
    echo "$brightness|$icon"
}

# Read hyprsunset configuration
read_hyprsunset_config() {
    local currentTemp currentGamma toggle_mode
    
    # Create config if it doesn't exist
    if [ ! -f "$sunsetConf" ]; then
        printf "%d|%d|%d\n" "$default_temp" "$default_gamma" 1 >"$sunsetConf"
    fi
    
    # Read current settings (PSV format: temp|gamma|state)
    IFS='|' read -r currentTemp currentGamma toggle_mode <"$sunsetConf"
    [ -z "$currentTemp" ] && currentTemp=$default_temp
    [ -z "$currentGamma" ] && currentGamma=$default_gamma
    [ -z "$toggle_mode" ] && toggle_mode=1
    
    echo "$currentTemp|$currentGamma|$toggle_mode"
}

# Get current running temperature from hyprctl
get_running_temp() {
    hyprctl hyprsunset temperature 2>/dev/null || echo "$default_temp"
}

# Check if hyprsunset process is running
is_hyprsunset_running() {
    pgrep -x "hyprsunset" >/dev/null
}

# Get hyprsunset status and temperature
get_hyprsunset_info() {
    local config_info currentTemp currentGamma toggle_mode
    local current_running_temp hs_icon temp
    
    # Read configuration
    config_info=$(read_hyprsunset_config)
    IFS='|' read -r currentTemp currentGamma toggle_mode <<< "$config_info"
    
    # Determine status
    if [[ $toggle_mode -eq 1 ]] && is_hyprsunset_running; then
        hs_icon='󰈈'  # Active icon
        current_running_temp=$(get_running_temp)
        
        # Use running temp if different from default, otherwise show configured temp
        if [[ $current_running_temp != $default_temp ]]; then
            temp="$current_running_temp"
        else
            temp="Identity"
        fi
    else
        hs_icon=''  # Inactive icon  
        temp='OFF'
    fi
    
    echo "$temp|$hs_icon"
}

# Determine color based on temperature
get_temp_color() {
    local temp=$1
    
    # Return early if not a number
    if ! [[ "$temp" =~ ^[0-9]+$ ]]; then
        echo "$temp"
        return
    fi
    
    # Temperature color mapping (same as hyprsunset.sh)
    if ((temp >= 10000)); then
        echo "<span color='#8b0000'><b>${temp}K</b></span>"
    elif ((temp >= 8000)); then
        echo "<span color='#ff6347'><b>${temp}K</b></span>"
    elif ((temp >= 6000)); then
        echo "<b>${temp}K</b>"
    elif ((temp >= 5000)); then
        echo "<span color='#ffa500'><b>${temp}K</b></span>"
    elif ((temp >= 4000)); then
        echo "<span color='#ff8c00'><b>${temp}K</b></span>"
    elif ((temp >= 3000)); then
        echo "<span color='#ff471a'><b>${temp}K</b></span>"
    elif ((temp >= 2000)); then
        echo "<span color='#d22f2f'><b>${temp}K</b></span>"
    elif ((temp >= 1000)); then
        echo "<span color='#ad1f2f'><b>${temp}K</b></span>"
    else
        echo "<b>${temp}K</b>"
    fi
}

# Format temperature display for preview
format_temp_display() {
    local temp=$1
    
    if [[ $temp == 'OFF' ]]; then
        echo '<span size="large" weight="bold">OFF</span>'
    elif [[ $temp == 'Identity' ]]; then
        echo '<span size="large" weight="bold">Identity</span>'
    else
        # Get colored temperature
        local colored_temp
        colored_temp=$(get_temp_color "$temp")
        # Adapt for preview formatting
        echo "$colored_temp" | sed 's/<b>/<span size="large" weight="bold">/g; s/<\/b>/<\/span>/g; s/K<\/span>/<span size="x-small" rise="3000">K<\/span><\/span>/g'
    fi
}

# Generate status JSON
generate_status() {
    local brightness_info hyprsunset_info
    local brightness brightness_icon temp hs_icon temp_display
    local format tooltip config_info currentTemp currentGamma toggle_mode
    
    # Get information
    brightness_info=$(get_brightness_info)
    hyprsunset_info=$(get_hyprsunset_info)
    config_info=$(read_hyprsunset_config)
    
    # Parse results
    IFS='|' read -r brightness brightness_icon <<< "$brightness_info"
    IFS='|' read -r temp hs_icon <<< "$hyprsunset_info"
    IFS='|' read -r currentTemp currentGamma toggle_mode <<< "$config_info"
    
    # Format temperature display
    temp_display=$(format_temp_display "$temp")
    
    # Create formatted output (matching volumecontrol pattern)
    format='<sup><span size="small" rise="1000">'$brightness_icon'</span> <span size="large" weight="bold">'$brightness'<span size="x-small" rise="1000">%</span></span></sup>\n<sub><span size="small" rise="1000">'$hs_icon'</span> '$temp_display'</sub>'
    
    # Create tooltip with current status
    local status_text
    if [[ $toggle_mode -eq 1 ]] && is_hyprsunset_running; then
        if [[ $temp == 'Identity' ]]; then
            status_text="Identity (${currentTemp}K saved)"
        else
            status_text="$temp"
        fi
    else
        status_text="OFF (${currentTemp}K saved)"
    fi
    
    tooltip='󰃠 Brightness: '$brightness'%\n󰈈 Hyprsunset: '$status_text'\n\n󰍉 Scroll: Brightness ±1%\n󰀨 Click: Toggle Hyprsunset\n󰘶 Right-click: Temp ±250K'
    
    # Output JSON
    jq -n --arg text "$format" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
}

# Generate detailed hyprsunset status (like original script)
generate_hyprsunset_status() {
    local config_info currentTemp currentGamma toggle_mode
    local current_running_temp text_output alt_text tooltip_text
    local temp_colored gamma_colored
    
    # Read configuration
    config_info=$(read_hyprsunset_config)
    IFS='|' read -r currentTemp currentGamma toggle_mode <<< "$config_info"
    
    # Determine status
    if [[ $toggle_mode -eq 1 ]] && is_hyprsunset_running; then
        text_output="󰈈"  # Filled eye - active
        alt_text="active"
        current_running_temp=$(get_running_temp)
        
        # Get colored values for tooltip
        temp_colored=$(get_temp_color "$current_running_temp")
        gamma_colored="<span color='$([ $currentGamma -ge 90 ] && echo "#00ff00" || [ $currentGamma -ge 70 ] && echo "#90ee90" || [ $currentGamma -le 30 ] && echo "#ffa500" || [ $currentGamma -le 20 ] && echo "#ff6347" || echo "")'><b>$currentGamma</b></span>"
        
        # Create rich tooltip
        tooltip_text="󰈈 <b>Hyprsunset Active</b>\n"
        tooltip_text+="󰔄 Temperature: $temp_colored\n"
        tooltip_text+="󰍉 Gamma: $gamma_colored\n"
        tooltip_text+="\n<i>󰀨 Click to Disable</i>"
    else
        text_output=""  # Unfilled eye - inactive
        alt_text="inactive"
        
        # Show saved settings in inactive tooltip
        local saved_temp_colored saved_gamma_colored
        saved_temp_colored=$(get_temp_color "$currentTemp")
        saved_gamma_colored="<span color='$([ $currentGamma -ge 90 ] && echo "#00ff00" || [ $currentGamma -ge 70 ] && echo "#90ee90" || [ $currentGamma -le 30 ] && echo "#ffa500" || [ $currentGamma -le 20 ] && echo "#ff6347" || echo "")'><b>$currentGamma</b></span>"
        
        tooltip_text=" <b>Hyprsunset: Inactive</b>\n"
        tooltip_text+="󰔄 Temperature: $saved_temp_colored\n"
        tooltip_text+="󰍉 Gamma: $saved_gamma_colored\n"
        tooltip_text+="\n<i>󰀨 Click to activate with saved settings</i>"
    fi
    
    # Output JSON
    jq -n --arg text "$text_output" --arg alt "$alt_text" --arg tooltip "$tooltip_text" '{text: $text, alt: $alt, tooltip: $tooltip}'
}

# Main execution
case "${1:-status}" in
    status|"")
        generate_status
        ;;
    brightness)
        get_brightness_info | cut -d'|' -f1
        ;;
    hyprsunset)
        get_hyprsunset_info | cut -d'|' -f1
        ;;
    hyprsunset-full)
        generate_hyprsunset_status
        ;;
    help|--help|-h)
        cat <<EOF
Usage: $(basename "$0") [COMMAND]

Commands:
    status          Generate full JSON status for waybar preview (default)
    brightness      Get current brightness percentage only
    hyprsunset      Get current hyprsunset temperature only  
    hyprsunset-full Generate full hyprsunset JSON status (like original script)
    help            Show this help message

Examples:
    $(basename "$0")                # Full preview status JSON
    $(basename "$0") status         # Full preview status JSON  
    $(basename "$0") brightness     # Just brightness number
    $(basename "$0") hyprsunset     # Just temperature
    $(basename "$0") hyprsunset-full # Full hyprsunset status
EOF
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$(basename "$0") help' for usage information"
        exit 1
        ;;
esac
