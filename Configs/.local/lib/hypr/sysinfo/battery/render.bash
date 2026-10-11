charging_icons=("󰂆 " "󰂇 " "󰂈 " "󰂉 " "󰂊 " "󰂋 " "󰂋 " "󰂋 " "󰂋 " "󰂋 " "󰂅 ") 
discharging_icons=("󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")
charging_status_icon=""
not_charging_status_icon="X"
default_status_icon="󰂇"

battery_render_format() {
    case "$1" in
    icon)
        if [[ "$battery_status" == "Charging" ]]; then
            echo -n "${charging_icons[$capacity_icon_index]} "
        else
            echo -n "${discharging_icons[$capacity_icon_index]} "
        fi
        ;;
    percentage)
        echo -n "$battery_percent% "
        ;;
    int)
        echo -n "$battery_percent "
        ;;
    status)
        echo -n "$battery_status "
        ;;
    status-icon)
        case "$battery_status" in
        "Charging")
            echo -n "$charging_status_icon "
            ;;
        "Not Charging")
            echo -n "$not_charging_status_icon "
            ;;
        *)
            echo -n "$default_status_icon "
            ;;
        esac
        ;;
    *)
        echo "Invalid format option: $1. Use 'icon', 'percentage', 'int', 'status', or 'status-icon'."
        exit 1
        ;;
    esac
}
