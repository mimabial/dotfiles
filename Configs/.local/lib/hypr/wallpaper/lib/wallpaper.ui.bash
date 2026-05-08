#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Help text + JSON and rofi selection helpers.

if ! declare -F rofi_effective_font_scale >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"
fi

show_help() {
  cat <<EOT
Usage: $(basename "$0") <command> [options]

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
    -b, --backend <backend>   Set wallpaper backend to use (awww, hyprpaper, etc.)
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

EOT
  exit 0
}

wallpaper_catalog_prepare_runtime() {
  local ensure_thumbs="${1:-0}"
  setIndex=0
  if ! wallpaper_theme_sources; then
    echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist"
    return 2
  fi

  Wall_Hashmap_Cached "${wallPathArray[@]}" || return 1
  # The trailing && is opportunistic; without an explicit return the function
  # would propagate the test's exit code (1) when ensure_thumbs=0, which is
  # the normal path.
  [[ "${ensure_thumbs}" -eq 1 ]] && Wall_Ensure_Thumbs "sqre"
  return 0
}

wallpaper_catalog_cache_paths() {
  local out_cache_home_name="$1"
  local out_cache_file_name="$2"
  local out_json_cache_name="$3"
  local resolved_cache_home=""
  local resolved_cache_file=""
  local resolved_json_cache=""

  resolved_cache_home="$(wallpaper_cache_root)"
  resolved_cache_file="$(wallpaper_hashmap_cache_file "${wallPathArray[@]}" 2>/dev/null || true)"
  resolved_json_cache="$(wallpaper_catalog_json_file "${wallPathArray[@]}" 2>/dev/null || true)"

  printf -v "${out_cache_home_name}" '%s' "${resolved_cache_home}"
  printf -v "${out_cache_file_name}" '%s' "${resolved_cache_file}"
  printf -v "${out_json_cache_name}" '%s' "${resolved_json_cache}"
}

wallpaper_catalog_print_cached_json_if_current() {
  local json_cache="$1"
  local cache_file="$2"
  local json_mtime=""
  local cache_mtime=""

  [[ -n "${json_cache}" && -f "${json_cache}" && -f "${cache_file}" ]] || return 1

  json_mtime="$(stat -c '%Y' -- "${json_cache}" 2>/dev/null || echo 0)"
  cache_mtime="$(stat -c '%Y' -- "${cache_file}" 2>/dev/null || echo 0)"
  if [[ "${json_mtime}" =~ ^[0-9]+$ && "${cache_mtime}" =~ ^[0-9]+$ ]] && ((json_mtime >= cache_mtime)); then
    cat "${json_cache}"
    return 0
  fi

  return 1
}

wallpaper_catalog_build_json() {
  local cache_home="$1"
  local wall_list_json=""
  local wall_hash_json=""

  wall_list_json=$(printf '%s\n' "${wallList[@]}" | jq -R . | jq -s .)
  wall_hash_json=$(printf '%s\n' "${wallHash[@]}" | jq -R . | jq -s .)

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

wallpaper_catalog_emit_and_cache_json() {
  local cache_home="$1"
  local json_cache="$2"
  local json_tmp=""

  if [[ -n "${json_cache}" ]]; then
    mkdir -p "$(dirname "${json_cache}")"
    json_tmp="${json_cache}.tmp"
  fi

  wallpaper_catalog_build_json "${cache_home}" | {
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

Wall_Json() {
  local ensure_thumbs=0
  local cache_home=""
  local cache_file=""
  local json_cache=""
  local prepare_status=0

  if [[ "${1:-}" == "--ensure-thumbs" ]]; then
    ensure_thumbs=1
    shift
  fi

  wallpaper_catalog_prepare_runtime "${ensure_thumbs}" || prepare_status=$?
  if ((prepare_status != 0)); then
    [[ "${prepare_status}" -eq 2 ]] && exit 0
    exit "${prepare_status}"
  fi
  wallpaper_catalog_cache_paths cache_home cache_file json_cache

  wallpaper_catalog_print_cached_json_if_current "${json_cache}" "${cache_file}" && return 0
  wallpaper_catalog_emit_and_cache_json "${cache_home}" "${json_cache}"
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
  local border_radius=0
  local elem_border=0
  local elm_width=0
  local max_avail=0
  local col_count=0

  border_radius="${HYPR_RUNTIME_BORDER_RADIUS:-${HYPR_BORDER_RADIUS:-0}}"
  [[ "${border_radius}" =~ ^[0-9]+$ ]] || border_radius=0
  elem_border=$((border_radius * 2))
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
    -sync
    -no-custom
    -show-icons
    -display-column-separator ":::"
    -display-columns 1
    -kb-accept-entry "Control+j,Control+m,Return,KP_Enter"
    -kb-row-select ""
    -me-select-entry ""
    -me-accept-entry MousePrimary
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
  local selected_row="$2"
  local selected_path=""

  selected_path="$(awk -F ':::' '{print $2}' <<<"${selected_row}")"
  [[ -n "${selected_path}" ]] || return 1

  jq -r --arg path "${selected_path}" \
    '.[] | select(.path == $path) | [.basename, .path, .sqre] | @tsv' \
    "${wall_json_file}" \
    | head -n1
}

wallpaper_rofi_entries() {
  local wall_json_file="$1"

  jq -r '.[] | "\(.basename):::\(.path):::\(.sqre)\u0000icon\u001f\(.sqre)"' "${wall_json_file}"
}

Wall_Select() {
  local font_scale="" font_name="" selected_entry="" wall_json_file="" selected_row="" rofi_status=0
  wall_json_file="$(mktemp)"
  font_scale="$(rofi_effective_font_scale "${ROFI_WALLPAPER_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_WALLPAPER_FONT:-$ROFI_FONT}")"
  Wall_Json --ensure-thumbs >"${wall_json_file}"
  selected_row="$(wallpaper_selected_row "${wall_json_file}")"
  local -a rofi_args
  wallpaper_select_rofi_args "${font_scale}" "${font_name}" "${selected_row}"

  selected_entry="$(wallpaper_rofi_entries "${wall_json_file}" | rofi "${rofi_args[@]}")" || rofi_status=$?

  if ((rofi_status != 0)) && [[ -z "${selected_entry}" ]]; then
    rm -f "${wall_json_file}"
    exit 0
  fi

  [[ -z "${selected_entry}" ]] && {
    rm -f "${wall_json_file}"
    exit 0
  }

  if [[ "${selected_entry}" != *":::"* ]]; then
    rm -f "${wall_json_file}"
    print_log -err "wallpaper" " Invalid wallpaper selection: ${selected_entry}"
    exit 1
  fi

  IFS=$'\t' read -r selected_wallpaper selected_wallpaper_path selected_thumbnail < <(wallpaper_selected_fields "${wall_json_file}" "${selected_entry}")
  rm -f "${wall_json_file}"
  export selected_wallpaper selected_wallpaper_path selected_thumbnail

  if [[ -z "${selected_wallpaper}" || -z "${selected_wallpaper_path}" ]]; then
    print_log -err "wallpaper" " No wallpaper selected"
    exit 0
  fi
}
