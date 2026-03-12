#!/usr/bin/env bash

# Help text + JSON and rofi selection helpers.

show_help() {
  cat <<EOT
Usage: $(basename "$0") --[options|flags] [parameters]
options:
    -j, --json                List wallpapers in JSON format to STDOUT
    -S, --select              Select wallpaper using rofi
    -n, --next                Set next wallpaper
    -p, --previous            Set previous wallpaper
    -r, --random              Set random wallpaper
    -s, --set <file>          Set specified wallpaper
        --start               Start/apply current wallpaper to backend
    -g, --get                 Get current wallpaper of specified backend
    -o, --output <file>       Copy current wallpaper to specified file
        --link                Resolved the linked wallpaper according to the theme
    -t  --filetypes <types>   Specify file types to override (colon-separated ':')
    -h, --help                Display this help message

flags:
    -b, --backend <backend>   Set wallpaper backend to use (swww, hyprpaper, etc.)
    -G, --global              Set wallpaper as global
        --clean-thumbs        Remove cached thumbs with no matching wallpapers


notes:
    .   --backend <backend> is also use to cache wallpapers/background images e.g. hyprlock
           when '--backend hyprlock' is used, the wallpaper will be cached in
           ~/.cache/hypr/wallpaper/current/hyprlock.png

    .   --global flag is used to set the wallpaper as global, this means all
         thumbnails will be updated to reflect the new wallpaper

    .   --output <path> is used to copy the current wallpaper to the specified path
            We can use this to have a copy of the wallpaper to '/var/tmp' where ly or
            any systemwide application can access it
EOT
  exit 0
}

Wall_Json() {
  local ensure_thumbs=0
  if [[ "${1}" == "--ensure-thumbs" ]]; then
    ensure_thumbs=1
    shift
  fi

  setIndex=0
  if ! wallpaper_theme_sources; then
    echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist"
    exit 0
  fi

  Wall_Hashmap_Cached "${wallPathArray[@]}"
  if [[ "${ensure_thumbs}" -eq 1 ]]; then
    Wall_Ensure_Thumbs "sqre"
  fi

  local wall_list_json wall_hash_json cache_home
  wall_list_json=$(printf '%s\n' "${wallList[@]}" | jq -R . | jq -s .)
  wall_hash_json=$(printf '%s\n' "${wallHash[@]}" | jq -R . | jq -s .)
  cache_home="$(wallpaper_cache_root)"

  jq -n --argjson wallList "${wall_list_json}" --argjson wallHash "${wall_hash_json}" --arg cacheHome "${cache_home}" '
        [range(0; $wallList | length) as $i |
            {
                path: $wallList[$i],
                hash: $wallHash[$i],
                basename: ($wallList[$i] | split("/") | last),
                thmb: "\($cacheHome)/thumbs/\($wallHash[$i]).thmb",
                sqre: "\($cacheHome)/thumbs/\($wallHash[$i]).sqre",
                blur: "\($cacheHome)/thumbs/\($wallHash[$i]).blur",
                quad: "\($cacheHome)/thumbs/\($wallHash[$i]).quad",
                rofi_sqre: "\($wallList[$i] | split("/") | last):::\($wallList[$i]):::\($cacheHome)/thumbs/\($wallHash[$i]).sqre\u0000icon\u001f\($cacheHome)/thumbs/\($wallHash[$i]).sqre",
                rofi_thmb: "\($wallList[$i] | split("/") | last):::\($wallList[$i]):::\($cacheHome)/thumbs/\($wallHash[$i]).thmb\u0000icon\u001f\($cacheHome)/thumbs/\($wallHash[$i]).thmb",
                rofi_blur: "\($wallList[$i] | split("/") | last):::\($wallList[$i]):::\($cacheHome)/thumbs/\($wallHash[$i]).blur\u0000icon\u001f\($cacheHome)/thumbs/\($wallHash[$i]).blur",
                rofi_quad: "\($wallList[$i] | split("/") | last):::\($wallList[$i]):::\($cacheHome)/thumbs/\($wallHash[$i]).quad\u0000icon\u001f\($cacheHome)/thumbs/\($wallHash[$i]).quad"
            }
        ]
    '
}

Wall_Select() {
  font_scale="${ROFI_WALLPAPER_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  # Set font name.
  font_name=${ROFI_WALLPAPER_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  # Set rofi font override.
  font_override="* {font: \"${font_name} ${font_scale}\";}"

  # shellcheck disable=SC2154
  elem_border=$((hypr_border * 3))

  # Scale for monitor.
  mon_data=$(hyprctl -j monitors)
  mon_x_res=$(jq '.[] | select(.focused==true) | if (.transform % 2 == 0) then .width else .height end' <<<"${mon_data}")
  mon_scale=$(jq '.[] | select(.focused==true) | .scale' <<<"${mon_data}" | sed "s/\.//")

  mon_x_res=${mon_x_res:-1920}
  mon_scale=${mon_scale:-1}
  mon_x_res=$((mon_x_res * 100 / mon_scale))

  # Generate config.
  elm_width=$(((28 + 8 + 5) * font_scale))
  max_avail=$((mon_x_res - (4 * font_scale)))
  col_count=$((max_avail / elm_width))

  r_override="window{width:100%;height:100%;fullscreen:true;}
    listview{columns:${col_count};spacing:5em;}
    element{border-radius:${elem_border}px;
    orientation:vertical;margin-bottom:1em;}
    element-icon{size:27em;border-radius:0em;}
    element-text{padding:1em;}"

  # Launch rofi menu.
  local entry wall_json_file selected_row current_hash
  wall_json_file="$(mktemp)"
  Wall_Json --ensure-thumbs >"${wall_json_file}"

  selected_row=""
  if [[ -e "${wallSet}" ]]; then
    current_hash="$(set_hash "${wallSet}")"
    if [[ -n "${current_hash}" ]]; then
      selected_row="$(jq -r --arg hash "${current_hash}" '[.[].hash] | index($hash) // empty' "${wall_json_file}")"
    fi
  fi

  local -a rofi_args
  rofi_args=(
    -dmenu -i
    -display-column-separator ":::"
    -display-columns 1
    -show-icons
    -theme-str "${font_override}"
    -theme-str "${r_override}"
    -theme-str "listview { show-icons: true; }"
    -theme "${ROFI_WALLPAPER_STYLE:-wallpaper}"
  )
  if [[ -n "${selected_row}" ]]; then
    rofi_args+=(-selected-row "${selected_row}")
  fi

  entry=$(jq -r '.[].rofi_sqre' "${wall_json_file}" | rofi "${rofi_args[@]}")
  rm -f "${wall_json_file}"

  [[ -z "${entry}" ]] && exit 0

  selected_thumbnail="$(awk -F ':::' '{print $3}' <<<"${entry}")"
  selected_wallpaper_path="$(awk -F ':::' '{print $2}' <<<"${entry}")"
  selected_wallpaper="$(awk -F ':::' '{print $1}' <<<"${entry}")"
  export selected_wallpaper selected_wallpaper_path selected_thumbnail

  if [[ -z "${selected_wallpaper}" ]]; then
    print_log -err "wallpaper" " No wallpaper selected"
    exit 0
  fi
}
