#!/usr/bin/env bash

pkill rofi && exit 0
[[ "${DENV_SHELL_INIT}" -ne 1 ]] && eval "$(denv-shell init)"

# define paths and files
cache_dir="${DENV_CACHE_HOME:-$HOME/.cache/denv}"
favorites_file="${cache_dir}/landing/cliphist_favorites"
[ -f "$HOME/.cliphist_favorites" ] && favorites_file="$HOME/.cliphist_favorites"
cliphist_style="${ROFI_CLIPHIST_STYLE:-clipboard}"
del_mode=false

# Calculate clipboard danger level for system performance
get_clipboard_danger_level() {
    local count=0
    local total_size=0
    local max_line_length=0
    local large_entries=0
    local binary_entries=0
    
    # Check if cliphist has any entries
    if ! cliphist list >/dev/null 2>&1; then
        echo "SAFE"
        return 0
    fi
    
    # Analyze each clipboard entry
    while IFS=$'\t' read -r id content; do
        ((count++))
        
        # Decode the entry to get actual content
        local decoded
        decoded=$(echo -e "${id}\t${content}" | cliphist decode 2>/dev/null)
        
        # Check for binary data
        if [[ "$content" == *"[[ binary data"* ]]; then
            ((binary_entries++))
            continue
        fi
        
        # Calculate size and line length
        local entry_size=${#decoded}
        total_size=$((total_size + entry_size))
        
        # Check for very large single entries (>1MB)
        if [[ $entry_size -gt 1048576 ]]; then
            ((large_entries++))
        fi
        
        # Find longest line in this entry
        while IFS= read -r line; do
            local line_length=${#line}
            if [[ $line_length -gt $max_line_length ]]; then
                max_line_length=$line_length
            fi
        done <<< "$decoded"
        
    done < <(cliphist list)
    
    # Determine danger level based on multiple factors
    local danger_score=0
    
    # Count factor (0-3 points)
    if [[ $count -gt 1000 ]]; then
        danger_score=$((danger_score + 3))
    elif [[ $count -gt 500 ]]; then
        danger_score=$((danger_score + 2))
    elif [[ $count -gt 100 ]]; then
        danger_score=$((danger_score + 1))
    fi
    
    # Total size factor (0-4 points)
    if [[ $total_size -gt 52428800 ]]; then  # >50MB
        danger_score=$((danger_score + 4))
    elif [[ $total_size -gt 10485760 ]]; then  # >10MB
        danger_score=$((danger_score + 3))
    elif [[ $total_size -gt 5242880 ]]; then   # >5MB
        danger_score=$((danger_score + 2))
    elif [[ $total_size -gt 1048576 ]]; then   # >1MB
        danger_score=$((danger_score + 1))
    fi
    
    # Large entries factor (0-2 points)
    if [[ $large_entries -gt 5 ]]; then
        danger_score=$((danger_score + 2))
    elif [[ $large_entries -gt 0 ]]; then
        danger_score=$((danger_score + 1))
    fi
    
    # Long line factor (0-2 points)
    if [[ $max_line_length -gt 50000 ]]; then
        danger_score=$((danger_score + 2))
    elif [[ $max_line_length -gt 10000 ]]; then
        danger_score=$((danger_score + 1))
    fi
    
    # Binary entries factor (0-1 point)
    if [[ $binary_entries -gt 10 ]]; then
        danger_score=$((danger_score + 1))
    fi
    
    # Return danger level based on score
    if [[ $danger_score -ge 7 ]]; then
        echo "xx"
    elif [[ $danger_score -ge 4 ]]; then
        echo "xo"
    elif [[ $danger_score -ge 2 ]]; then
        echo "x-"
    else
        echo "--"
    fi
}

# Get danger level icon for waybar
get_danger_icon() {
    local level
    level=$(get_clipboard_danger_level)
    case "$level" in
        "CRITICAL") echo "🔴" ;;
        "HIGH")     echo "🟠" ;;
        "MEDIUM")   echo "🟡" ;;
        "SAFE")     echo "🟢" ;;
    esac
}

# process clipboard selections for multi-select mode
process_selections() {
    if [ true != "${del_mode}" ]; then
        # Read the entire input into an array
        mapfile -t lines #! Not POSIX compliant
        # Get the total number of lines
        total_lines=${#lines[@]}

        # handle special commands
        if [[ "${lines[0]}" = ":d:e:l:e:t:e:"* ]]; then
            "${0}" --delete
            return
        elif [[ "${lines[0]}" = ":w:i:p:e:"* ]]; then
            "${0}" --wipe
            return
        elif [[ "${lines[0]}" = ":b:a:r:"* ]] || [[ "${lines[0]}" = *":c:o:p:y:"* ]]; then
            "${0}" --copy
            return
        elif [[ "${lines[0]}" = ":f:a:v:"* ]]; then
            "${0}" --favorites
            return
        elif [[ "${lines[0]}" = ":o:p:t:"* ]]; then
            "${0}"
            return
        fi

        # process regular clipboard items
        local output=""
        # Iterate over each line in the array
        for ((i = 0; i < total_lines; i++)); do
            local line="${lines[$i]}"
            local decoded_line
            decoded_line="$(echo -e "$line\t" | cliphist decode)"
            if [ $i -lt $((total_lines - 1)) ]; then
                printf -v output '%s%s\n' "$output" "$decoded_line"
            else
                printf -v output '%s%s' "$output" "$decoded_line"
            fi
        done
        echo -n "$output"
    else
        # handle delete mode
        while IFS= read -r line; do
            if [[ "${line}" = ":w:i:p:e:"* ]]; then
                "${0}" --wipe
                break
            elif [[ "${line}" = ":b:a:r:"* ]]; then
                "${0}" --delete
                break
            elif [ -n "$line" ]; then
                cliphist delete <<<"${line}"
                notify-send "Deleted" "${line}"
            fi
        done
        exit 0
    fi
}

# check if content is binary and handle accordingly
check_content() {
    local line
    read -r line
    if [[ ${line} == *"[[ binary data"* ]]; then
        cliphist decode <<<"$line" | wl-copy
        local img_idx
        img_idx=$(awk -F '\t' '{print $1}' <<<"$line")
        local temp_preview="${DENV_RUNTIME_DIR}/pastebin-preview_${img_idx}"
        wl-paste >"${temp_preview}"
        notify-send -a "Pastebin:" "Preview: ${img_idx}" -i "${temp_preview}" -t 2000
        return 1
    fi
}

# execute rofi with common parameters
run_rofi() {
    local placeholder="$1"
    shift

    rofi -dmenu \
        -theme-str "entry { placeholder: \"${placeholder}\";}" \
        -theme-str "${font_override}" \
        -theme-str "${r_override}" \
        -theme-str "${rofi_position}" \
        -theme "${cliphist_style}" \
        "$@"
}

# setup rofi configuration
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
    r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;}wallbox{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"
}

# create favorites directory if it doesn't exist
ensure_favorites_dir() {
    local dir
    dir=$(dirname "$favorites_file")
    [ -d "$dir" ] || mkdir -p "$dir"
}

# process favorites file into an array of decoded lines for rofi
prepare_favorites_for_display() {
    if [ ! -f "$favorites_file" ] || [ ! -s "$favorites_file" ]; then
        return 1
    fi

    # read each Base64 encoded favorite as a separate line
    mapfile -t favorites <"$favorites_file"

    # prepare list of representations for rofi
    decoded_lines=()
    for favorite in "${favorites[@]}"; do
        local decoded_favorite
        decoded_favorite=$(echo "$favorite" | base64 --decode)
        # replace newlines with spaces for rofi display
        local single_line_favorite
        single_line_favorite=$(echo "$decoded_favorite" | tr '\n' ' ')
        decoded_lines+=("$single_line_favorite")
    done

    return 0
}

# display clipboard history and copy selected item
show_history() {
    local selected_item
    selected_item=$( (
        echo -e ":f:a:v:\t📌 Favorites"
        echo -e ":o:p:t:\t⚙️ Options"
        cliphist list
    ) | run_rofi " 📜 History..." -multi-select -i -display-columns 2 -selected-row 2)

    [ -n "${selected_item}" ] || exit 0

    if echo -e "${selected_item}" | check_content; then
        process_selections <<<"${selected_item}" | wl-copy
        paste_string "${@}"
        echo -e "${selected_item}\t" | cliphist delete
    else
        # binary content - handled by check_content
        paste_string "${@}"
        exit 0
    fi
}

# delete items from clipboard history
delete_items() {
    export del_mode=true
    cliphist list | run_rofi " 🗑️ Delete" -multi-select -i -display-columns 2 | process_selections
}

# favorite clipboard items
view_favorites() {
    prepare_favorites_for_display || {
        notify-send "No favorites."
        return
    }

    local selected_favorite
    selected_favorite=$(printf "%s\n" "${decoded_lines[@]}" | run_rofi "📌 View Favorites")

    if [ -n "$selected_favorite" ]; then
        # Find the index of the selected favorite
        local index
        index=$(printf "%s\n" "${decoded_lines[@]}" | grep -nxF "$selected_favorite" | cut -d: -f1)

        # Use the index to get the Base64 encoded favorite
        if [ -n "$index" ]; then
            local selected_encoded_favorite="${favorites[$((index - 1))]}"
            echo "$selected_encoded_favorite" | base64 --decode | wl-copy
            paste_string "${@}"
            notify-send "Copied to clipboard."
        else
            notify-send "Error: Selected favorite not found."
        fi
    fi
}

# add item to favorites
add_to_favorites() {
    ensure_favorites_dir

    local item
    item=$(cliphist list | run_rofi "➕ Add to Favorites...")

    if [ -n "$item" ]; then
        local full_item
        full_item=$(echo "$item" | cliphist decode)

        local encoded_item
        encoded_item=$(echo "$full_item" | base64 -w 0)

        # Check if the item is already in the favorites file
        if [ -f "$favorites_file" ] && grep -Fxq "$encoded_item" "$favorites_file"; then
            notify-send "Item is already in favorites."
        else
            echo "$encoded_item" >>"$favorites_file"
            notify-send "Added to favorites."
        fi
    fi
}

# delete from favorites
delete_from_favorites() {
    prepare_favorites_for_display || {
        notify-send "No favorites to remove."
        return
    }

    local selected_favorite
    selected_favorite=$(printf "%s\n" "${decoded_lines[@]}" | run_rofi "➖ Remove from Favorites...")

    if [ -n "$selected_favorite" ]; then
        local index
        index=$(printf "%s\n" "${decoded_lines[@]}" | grep -nxF "$selected_favorite" | cut -d: -f1)

        if [ -n "$index" ]; then
            local selected_encoded_favorite="${favorites[$((index - 1))]}"

            # Handle case where only one item is present
            if [ "$(wc -l <"$favorites_file")" -eq 1 ]; then
                : >"$favorites_file"
            else
                grep -vF -x "$selected_encoded_favorite" "$favorites_file" >"${favorites_file}.tmp" &&
                    mv "${favorites_file}.tmp" "$favorites_file"
            fi
            notify-send "Item removed from favorites."
        else
            notify-send "Error: Selected favorite not found."
        fi
    fi
}

# clear all favorites
clear_favorites() {
    if [ -f "$favorites_file" ] && [ -s "$favorites_file" ]; then
        local confirm
        confirm=$(echo -e "Yes\nNo" | run_rofi "☢️ Clear All Favorites?")

        if [ "$confirm" = "Yes" ]; then
            : >"$favorites_file"
            notify-send "All favorites have been deleted."
        fi
    else
        notify-send "No favorites to delete."
    fi
}

# manage favorites
manage_favorites() {
    local manage_action
    manage_action=$(echo -e "Add to Favorites\nDelete from Favorites\nClear All Favorites" |
        run_rofi "📓 Manage Favorites")

    case "${manage_action}" in
    "Add to Favorites")
        add_to_favorites
        ;;
    "Delete from Favorites")
        delete_from_favorites
        ;;
    "Clear All Favorites")
        clear_favorites
        ;;
    *)
        [ -n "${manage_action}" ] || return 0
        echo "Invalid action"
        exit 1
        ;;
    esac
}

# clear clipboard history
clear_history() {
    local confirm
    confirm=$(echo -e "Yes\nNo" | run_rofi "☢️ Clear Clipboard History?")

    if [ "$confirm" = "Yes" ]; then
        cliphist wipe
        notify-send "Clipboard history cleared."
    fi
}

# show help message
show_help() {
    cat <<EOF
Options:
  -c  | --copy | History                Show clipboard history and copy selected item
  -d  | --delete | Delete               Delete selected item from clipboard history
  -f  | --favorites| View Favorites     View favorite clipboard items
  -mf | -manage-fav | Manage Favorites  Manage favorite clipboard items
  -w  | --wipe | Clear History          Clear clipboard history
  -h  | --help | Help                   Display this help message
  --danger-level                        Show clipboard performance danger level
  --danger-icon                         Show danger level as icon (for waybar)

Note: To enable autopaste, install 'wtype' package.
EOF
    exit 0
}

# main function
main() {
    setup_rofi_config

    local main_action
    # show main menu if no arguments are passed
    if [ $# -eq 0 ]; then
        main_action=$(echo -e "History\nDelete\nView Favorites\nManage Favorites\nClear History" |
            run_rofi "🔎 Choose action")
    else
        main_action="$1"
    fi

    # process user selection
    case "${main_action}" in
    -c | --copy | "History")
        show_history "$@"
        ;;
    -d | --delete | "Delete")
        delete_items
        ;;
    -f | --favorites | "View Favorites")
        view_favorites "$@"
        ;;
    -mf | -manage-fav | "Manage Favorites")
        manage_favorites
        ;;
    -w | --wipe | "Clear History")
        clear_history
        ;;
    --danger-level)
        get_clipboard_danger_level
        ;;
    --danger-icon)
        get_danger_icon
        ;;
    -h | --help | *)
        [ -z "$main_action" ] && exit 0
        show_help
        ;;
    esac
}

# run main function
main "$@"
