#!/usr/bin/env bash

# Help text + JSON and rofi selection helpers.

if ! declare -F rofi_effective_font_scale >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"
fi

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
            We can use this to have a copy of the wallpaper in '/var/tmp' where
            systemwide applications can access it
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

  local wall_list_json wall_hash_json cache_home cache_file json_cache json_tmp
  cache_home="$(wallpaper_cache_root)"
  cache_file="$(wallpaper_hashmap_cache_file "${wallPathArray[@]}" 2>/dev/null || true)"
  json_cache="$(wallpaper_catalog_json_file "${wallPathArray[@]}" 2>/dev/null || true)"

  if [[ -n "${json_cache}" && -f "${json_cache}" && -f "${cache_file}" ]]; then
    local json_mtime cache_mtime
    json_mtime="$(stat -c '%Y' -- "${json_cache}" 2>/dev/null || echo 0)"
    cache_mtime="$(stat -c '%Y' -- "${cache_file}" 2>/dev/null || echo 0)"
    if [[ "${json_mtime}" =~ ^[0-9]+$ && "${cache_mtime}" =~ ^[0-9]+$ ]] && ((json_mtime >= cache_mtime)); then
      cat "${json_cache}"
      return 0
    fi
  fi

  wall_list_json=$(printf '%s\n' "${wallList[@]}" | jq -R . | jq -s .)
  wall_hash_json=$(printf '%s\n' "${wallHash[@]}" | jq -R . | jq -s .)

  if [[ -n "${json_cache}" ]]; then
    mkdir -p "$(dirname "${json_cache}")"
    json_tmp="${json_cache}.tmp"
  fi

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
    ' | {
    if [[ -n "${json_tmp}" ]]; then
      tee "${json_tmp}"
    else
      cat
    fi
  }

  if [[ -n "${json_tmp}" && -f "${json_tmp}" ]]; then
    mv -f "${json_tmp}" "${json_cache}"
  fi
}

wallpaper_select_monitor_width() {
  local mon_x_res=""

  read -r mon_x_res _ < <(rofi_focused_monitor_logical_size)
  [[ "${mon_x_res}" =~ ^[0-9]+$ ]] || mon_x_res=1920
  printf '%s\n' "${mon_x_res}"
}

wallpaper_select_theme_override() {
  local font_scale="$1"
  local mon_x_res=""
  local elem_border=0
  local elm_width=0
  local max_avail=0
  local col_count=0

  elem_border=$((hypr_border * 2))
  mon_x_res="$(wallpaper_select_monitor_width)"
  elm_width=$(((28 + 8 + 5) * font_scale))
  max_avail=$((mon_x_res - (4 * font_scale)))
  col_count=$((max_avail / elm_width))

  cat <<EOF
listview{columns:${col_count};}
element{border-radius:${elem_border}px;}
EOF
}

wallpaper_select_rofi_args() {
  local font_scale="$1"
  local font_name="$2"
  local selected_row="$3"
  local font_override=""
  local r_override=""
  local opacity_override=""

  font_override="* {font: \"${font_name} ${font_scale}\";}"
  r_override="$(wallpaper_select_theme_override "${font_scale}")"
  opacity_override="$(rofi_active_opacity_override)"

  rofi_args=(
    -dmenu -i
    -format i
    -display-column-separator ":::"
    -display-columns 1
    -show-icons
    -theme-str "${font_override}"
    -theme-str "${r_override}"
    -theme-str "listview { show-icons: true; }"
    -theme "${ROFI_WALLPAPER_STYLE:-wallpaper}"
  )
  [[ -n "${opacity_override}" ]] && rofi_args+=(-theme-str "${opacity_override}")
  [[ -n "${selected_row}" ]] && rofi_args+=(-selected-row "${selected_row}")
}

wallpaper_selected_row() {
  local wall_json_file="$1"
  local current_hash=""

  [[ -e "${active_wallpaper_link}" ]] || return 0
  current_hash="$(set_hash "${active_wallpaper_link}")"
  [[ -n "${current_hash}" ]] || return 0
  jq -r --arg hash "${current_hash}" '[.[].hash] | index($hash) // empty' "${wall_json_file}"
}

wallpaper_selected_fields() {
  local wall_json_file="$1"
  local selected_index="$2"
  jq -r --argjson idx "${selected_index}" '[.[ $idx ].basename, .[ $idx ].path, .[ $idx ].sqre] | @tsv' "${wall_json_file}"
}

Wall_Select() {
  local font_scale="" font_name="" selected_index="" wall_json_file="" selected_row=""
  wall_json_file="$(mktemp)"
  font_scale="$(rofi_effective_font_scale "${ROFI_WALLPAPER_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_WALLPAPER_FONT:-$ROFI_FONT}")"
  Wall_Json --ensure-thumbs >"${wall_json_file}"
  selected_row="$(wallpaper_selected_row "${wall_json_file}")"
  local -a rofi_args
  wallpaper_select_rofi_args "${font_scale}" "${font_name}" "${selected_row}"

  selected_index="$(jq -r '.[].rofi_sqre' "${wall_json_file}" | rofi "${rofi_args[@]}")"

  [[ -z "${selected_index}" ]] && {
    rm -f "${wall_json_file}"
    exit 0
  }

  if [[ ! "${selected_index}" =~ ^[0-9]+$ ]]; then
    rm -f "${wall_json_file}"
    print_log -err "wallpaper" " Invalid selection index: ${selected_index}"
    exit 1
  fi

  IFS=$'\t' read -r selected_wallpaper selected_wallpaper_path selected_thumbnail < <(wallpaper_selected_fields "${wall_json_file}" "${selected_index}")
  rm -f "${wall_json_file}"
  export selected_wallpaper selected_wallpaper_path selected_thumbnail

  if [[ -z "${selected_wallpaper}" ]]; then
    print_log -err "wallpaper" " No wallpaper selected"
    exit 0
  fi
}
