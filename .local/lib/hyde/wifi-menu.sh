#!/usr/bin/env bash

# From hyde
pkill -u "$USER" rofi && exit 0
[[ "${HYDE_SHELL_INIT}" -ne 1 ]] && eval "$(hyde-shell init)"
cliphist_style="${ROFI_CLIPHIST_STYLE:-clipboard}"
placeholder="Search"

# From themes
type="$HOME/.config/rofi/launchers/type-5"
style='style-5.rasi'
theme="$type/$style"
prompt='Search'
mesg="Installed Packages : `pacman -Q | wc -l` (pacman)"
if [[ ( "$theme" == *'type-1'* ) || ( "$theme" == *'type-3'* ) || ( "$theme" == *'type-5'* ) ]]; then
	list_col='1'
	list_row='6'
elif [[ ( "$theme" == *'type-2'* ) || ( "$theme" == *'type-4'* ) ]]; then
	list_col='6'
	list_row='1'
fi

options=$(
  echo "  Manual Entry"
  echo "󰤮  Disable Wi-Fi"
)
option_disabled="󰤥  Enable Wi-Fi"

# Rofi window override
override_ssid="entry { placeholder: \"Enter SSID\"; } listview { lines: 0; padding: 20px 6px; }"
override_password="entry { placeholder: \"Enter password\"; } listview { lines: 0; padding: 20px 6px; }"
override_disabled="inputbar { children: [ "textbox-prompt-colon", "textbox-custom" ]; }"

# Prompt for password
get_password() {
  rofi -dmenu -password \
  -theme-str "${override_password}" \
     -theme-str "entry { placeholder: \"${placeholder}\";}" \
     -theme-str "${font_override}" \
     -theme-str "${r_override}" \
  -theme "${theme}" -p " " || pkill -x rofi
}

setup_rofi_config() {
    # font scale
    local font_scale="${ROFI_CLIPHIST_SCALE}"
    [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

    # set font name
    local font_name=${ROFI_CLIPHIST_FONT:-$ROFI_FONT}
    font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
    font_name=${font_name:-$(get_hyprConf "FONT")}

    # set rofi font override
    font_override="* {font: \"${font_name:-"JetBrainsMono Nerd Font"} ${font_scale}\";}"

    # border settings
    local hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
    local wind_border=$((hypr_border * 3 / 2))
    local elem_border=$((hypr_border == 0 ? 5 : hypr_border))

    # rofi position
    rofi_position=$(get_rofi_pos)
    # border width
    local hypr_width=${hypr_width:-"$(hyprctl -j getoption general:border_size | jq '.int')"}
    r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;} wallbox{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;} inputbar{border-radius:${elem_border}px;} listview{border-radius:${elem_border}px;} textbox-prompt-colon{border-radius:${elem_border}px;} textbox{border-radius:${elem_border}px;}"
    echo "r_override: $r_override" >&2
}

setup_rofi_config

wifi_list() {
  nmcli --fields "SECURITY,SSID" device wifi list |
    tail -n +2 |               # Skip the header line from nmcli output
    sed 's/  */ /g' |          # Replace multiple spaces with a single space
    sed -E "s/WPA*.?\S/󰤪 /g" | # Replace 'WPA*' with a Wi-Fi lock icon
    sed "s/^--/󰤨 /g" |         # Replace '--' (open networks) with an open Wi-Fi icon
    sed "s/󰤪  󰤪/󰤪/g" |         # Remove duplicate Wi-Fi lock icons
    sed "/--/d" |              # Remove lines containing '--' (empty SSIDs)
    awk '!seen[$0]++'          # Filter out duplicate SSIDs
}

while true; do
  # Get Wi-Fi status
  wifi_status=$(nmcli -fields WIFI g)

  case "$wifi_status" in
  *"enabled"*)
    selected_option=$(echo "$options"$'\n'"$(wifi_list)" |
      rofi -dmenu -i -selected-row 1 \
        -theme-str "entry { placeholder: \"${placeholder}\";}" \
        -theme-str "${font_override}" \
        -theme-str "${r_override}" \
        -theme-str 'textbox-prompt-colon { str: " "; }' \
        -theme "${theme}" || pkill -x rofi)
    ;;
  *"disabled"*)
    selected_option=$(echo "$option_disabled" |
      rofi -dmenu -i \
        -theme-str "entry { placeholder: \"${placeholder}\";}" \
        -theme-str "${font_override}" \
        -theme-str "${r_override}" \
        -theme-str "${override_disabled}" \
        -theme-str 'textbox-prompt-colon { str: "󰤥 "; }' \
        -theme "${theme}" \
        -theme-str "${override_disabled}" || pkill -x rofi)
    ;;
  esac

  # Extract selected SSID
  read -r selected_ssid <<<"${selected_option:3}"

  # Actions based on selected option
  case "$selected_option" in
  "")
    exit
    ;;
  *"Enable Wi-Fi")
    notify-send "Scanning for networks..." -i "package-installed-outdated"
    nmcli radio wifi on
    nmcli device wifi rescan
    sleep 3
    ;;
  *"Disable Wi-Fi")
    notify-send "Wi-Fi Disabled" -i "package-broken"
    nmcli radio wifi off
    exit
    ;;
  *"Manual Entry")
    # Prompt for SSID
    manual_ssid=$(rofi -dmenu \
     -theme-str "entry { placeholder: \"${placeholder}\";}" \
     -theme-str "${font_override}" \
     -theme-str "${r_override}" \
    -theme "${theme}" \
    -theme-str "${override_ssid}" \
    -p " " || pkill -x rofi)

    # Exit if no option is selected
    if [ -z "$manual_ssid" ]; then
      exit
    fi

    # Prompt for Wi-Fi password
    wifi_password=$(get_password)

    if [ -z "$wifi_password" ]; then
      # Without password
      if nmcli device wifi connect "$manual_ssid" | grep -q "successfully"; then
        notify-send "Connected to \"$manual_ssid\"." -i "package-installed-outdated"
        exit
      else
        notify-send "Failed to connect to \"$manual_ssid\"." -i "package-broken"
      fi
    else
      # With password
      if nmcli device wifi connect "$manual_ssid" password "$wifi_password" | grep -q "successfully"; then
        notify-send "Connected to \"$manual_ssid\"." -i "package-installed-outdated"
        exit
      else
        notify-send "Failed to connect to \"$manual_ssid\"." -i "package-broken"
      fi
    fi
    ;;
  *)
    # Get saved connections
    saved_connections=$(nmcli -g NAME connection)

    if echo "$saved_connections" | grep -qw "$selected_ssid"; then
      if nmcli connection up id "$selected_ssid" | grep -q "successfully"; then
        notify-send "Connected to \"$selected_ssid\"." -i "package-installed-outdated"
        exit
      else
        notify-send "Failed to connect to \"$selected_ssid\"." -i "package-broken"
      fi
    else
      # Handle secure network connection
      if [[ "$selected_option" =~ ^"󰤪" ]]; then
        wifi_password=$(get_password)
      fi

      if nmcli device wifi connect "$selected_ssid" password "$wifi_password" | grep -q "successfully"; then
        notify-send "Connected to \"$selected_ssid\"." -i "package-installed-outdated"
        exit
      else
        notify-send "Failed to connect to \"$selected_ssid\"." -i "package-broken"
      fi
    fi
    ;;
  esac
done
