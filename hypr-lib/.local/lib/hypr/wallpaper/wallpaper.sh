#!/usr/bin/env bash
# shellcheck disable=SC2154

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

# Lock file to prevent concurrent wallpaper operations
WALLPAPER_LOCK="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-switch.lock"
exec 202>"${WALLPAPER_LOCK}"
! flock -n 202 && {
  print_log -sec "wallpaper" -stat "wait" "Another wallpaper operation in progress, waiting..."
  flock 202
}
trap 'flock -u 202 2>/dev/null' EXIT

# // Help message
show_help() {
  cat <<EOF
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


notes: 
       --backend <backend> is also use to cache wallpapers/background images e.g. hyprlock
           when '--backend hyprlock' is used, the wallpaper will be cached in
           ~/.cache/hypr/wallpaper/current/hyprlock.png

       --global flag is used to set the wallpaper as global, this means all
         thumbnails will be updated to reflect the new wallpaper

       --output <path> is used to copy the current wallpaper to the specified path
            We can use this to have a copy of the wallpaper to '/var/tmp' where sddm or
            any systemwide application can access it  
EOF
  exit 0
}
#// Set and Cache Wallpaper

Wall_Cache() {

  # Experimental, set to 1 if stable
  if [[ "${WALLPAPER_RELOAD_ALL:-1}" -eq 1 ]] && [[ ${wallpaper_setter_flag} != "link" ]]; then
    print_log -sec "wallpaper" "Reloading themes and wallpapers"
    export reload_flag=1
  fi

  ln -fs "${wallList[setIndex]}" "${wallSet}"
  ln -fs "${wallList[setIndex]}" "${wallCur}"

  # Update hyprlock background
  command -v hyprlock.sh &>/dev/null && hyprlock.sh --background &

  if [ "${set_as_global}" == "true" ]; then
    print_log -sec "wallpaper" "Setting Wallpaper as global"
    "${LIB_DIR}/hypr/wallpaper/swwwallcache.sh" -w "${wallList[setIndex]}" &>/dev/null
    "${LIB_DIR}/hypr/theme/color.set.sh" "${wallList[setIndex]}"
    ln -fs "${thmbDir}/${wallHash[setIndex]}.sqre" "${wallSqr}"
    ln -fs "${thmbDir}/${wallHash[setIndex]}.thmb" "${wallTmb}"
    ln -fs "${thmbDir}/${wallHash[setIndex]}.blur" "${wallBlr}"
    ln -fs "${thmbDir}/${wallHash[setIndex]}.quad" "${wallQad}"
  fi

}

Wall_Change() {
  curWall="$(set_hash "${wallSet}")"
  for i in "${!wallHash[@]}"; do
    if [ "${curWall}" == "${wallHash[i]}" ]; then
      if [ "${1}" == "n" ]; then
        setIndex=$(((i + 1) % ${#wallList[@]}))
      elif [ "${1}" == "p" ]; then
        setIndex=$((i - 1))
      fi
      break
    fi
  done
  Wall_Cache "${wallList[setIndex]}"
}

Wall_Hashmap_Cached() {
  unset wallHash wallList

  local -a wall_sources=("$@")
  local -a supported_files=("gif" "jpg" "jpeg" "png" "${WALLPAPER_FILETYPES[@]}")
  if [[ ${#WALLPAPER_OVERRIDE_FILETYPES[@]} -gt 0 ]]; then
    supported_files=("${WALLPAPER_OVERRIDE_FILETYPES[@]}")
  fi

  local cache_root="${WALLPAPER_CACHE_DIR}"
  [[ -z "${cache_root}" ]] && cache_root="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/wallpaper"
  local cache_dir="${cache_root}/hashmap"
  local hash_cmd="${hashMech:-sha1sum}"

  local cache_key
  cache_key="$(printf '%s\n' "${wall_sources[@]}" "${supported_files[@]}" | "${hash_cmd}" | awk '{print $1}')"
  local cache_file="${cache_dir}/${cache_key}.tsv"
  mkdir -p "${cache_dir}"

  if [[ ${#wall_sources[@]} -eq 0 ]]; then
    get_hashmap "${wall_sources[@]}"
    return 0
  fi

  local -A cache_hash
  local -A cache_meta
  if [[ -f "${cache_file}" ]]; then
    while IFS=$'\t' read -r hash mtime size path; do
      [[ -n "${path}" ]] || continue
      cache_hash["${path}"]="${hash}"
      cache_meta["${path}"]="${mtime}"$'\t'"${size}"
    done < "${cache_file}"
  fi

  local regex_ext=""
  local ext
  for ext in "${supported_files[@]}"; do
    [[ -n "${ext}" ]] || continue
    if [[ -z "${regex_ext}" ]]; then
      regex_ext="${ext}"
    else
      regex_ext="${regex_ext}|${ext}"
    fi
  done
  [[ -z "${regex_ext}" ]] && regex_ext="gif|jpg|jpeg|png"

  local tmp_cache="${cache_file}.tmp"
  : > "${tmp_cache}"

  local wall_file wall_meta wall_hash
  while IFS= read -r -d '' wall_file; do
    wall_meta="$(stat -c '%Y\t%s' -- "${wall_file}" 2>/dev/null)" || continue
    if [[ "${cache_meta["${wall_file}"]}" == "${wall_meta}" ]]; then
      wall_hash="${cache_hash["${wall_file}"]}"
    else
      wall_hash="$("${hash_cmd}" "${wall_file}" | awk '{print $1}')"
    fi
    wallHash+=("${wall_hash}")
    wallList+=("${wall_file}")
    printf '%s\t%s\t%s\n' "${wall_hash}" "${wall_meta}" "${wall_file}" >> "${tmp_cache}"
  done < <(
    find -H "${wall_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" -print0 2>/dev/null | sort -z
  )

  if [[ ${#wallList[@]} -eq 0 ]]; then
    rm -f "${tmp_cache}"
    get_hashmap "${wall_sources[@]}"
    if [[ ${#wallList[@]} -gt 0 ]]; then
      tmp_cache="${cache_file}.tmp"
      : > "${tmp_cache}"
      local i
      for i in "${!wallList[@]}"; do
        wall_meta="$(stat -c '%Y\t%s' -- "${wallList[i]}" 2>/dev/null)" || continue
        printf '%s\t%s\t%s\n' "${wallHash[i]}" "${wall_meta}" "${wallList[i]}" >> "${tmp_cache}"
      done
      mv -f "${tmp_cache}" "${cache_file}"
    fi
    return 0
  fi

  mv -f "${tmp_cache}" "${cache_file}"
}

# * Method to list wallpapers from hashmaps into json
Wall_Json() {
  setIndex=0
  [ ! -d "${HYPR_THEME_DIR}" ] && echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist" && exit 0
  if [ -d "${HYPR_THEME_DIR}/wallpapers" ]; then
    wallPathArray=("${HYPR_THEME_DIR}/wallpapers")
  else
    wallPathArray=("${HYPR_THEME_DIR}")
  fi
  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")

  Wall_Hashmap_Cached "${wallPathArray[@]}" # get the hashmap provides wallList and wallHash

  # Prepare data for jq
  wallListJson=$(printf '%s\n' "${wallList[@]}" | jq -R . | jq -s .)
  wallHashJson=$(printf '%s\n' "${wallHash[@]}" | jq -R . | jq -s .)

  # Create JSON using jq
  jq -n --argjson wallList "$wallListJson" --argjson wallHash "$wallHashJson" --arg cacheHome "${WALLPAPER_CACHE_DIR:-${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/wallpaper}" '
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
                rofi_quad: "\($wallList[$i] | split("/") | last):::\($wallList[$i]):::\($cacheHome)/thumbs/\($wallHash[$i]).quad\u0000icon\u001f\($cacheHome)/thumbs/\($wallHash[$i]).quad",

            }
        ]
    '
}

Wall_Select() {
  font_scale="${ROFI_WALLPAPER_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  # set font name
  font_name=${ROFI_WALLPAPER_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  # set rofi font override
  font_override="* {font: \"${font_name} ${font_scale}\";}"

  # shellcheck disable=SC2154
  elem_border=$((hypr_border * 3))

  #// scale for monitor

  mon_data=$(hyprctl -j monitors)
  mon_x_res=$(jq '.[] | select(.focused==true) | if (.transform % 2 == 0) then .width else .height end' <<<"${mon_data}")
  mon_scale=$(jq '.[] | select(.focused==true) | .scale' <<<"${mon_data}" | sed "s/\.//")

  # Add fallback size
  mon_x_res=${mon_x_res:-1920}
  mon_scale=${mon_scale:-1}

  mon_x_res=$((mon_x_res * 100 / mon_scale))

  #// generate config

  elm_width=$(((28 + 8 + 5) * font_scale))
  max_avail=$((mon_x_res - (4 * font_scale)))
  col_count=$((max_avail / elm_width))

  r_override="window{width:100%;height:100%;fullscreen:true;}
    listview{columns:${col_count};spacing:5em;}
    element{border-radius:${elem_border}px;
    orientation:vertical;margin-bottom:1em;} 
    element-icon{size:27em;border-radius:0em;}
    element-text{padding:1em;}"

  #// launch rofi menu
  local entry
  entry=$(

    Wall_Json | jq -r '.[].rofi_sqre' | rofi -dmenu -i \
      -display-column-separator ":::" \
      -display-columns 1 \
      -show-icons \
      -theme-str "${font_override}" \
      -theme-str "${r_override}" \
      -theme-str "listview { show-icons: true; }" \
      -theme "${ROFI_WALLPAPER_STYLE:-wallpaper}" \
      -select "$(basename "$(readlink "$wallSet")")"
  )
  selected_thumbnail="$(awk -F ':::' '{print $3}' <<<"${entry}")"
  selected_wallpaper_path="$(awk -F ':::' '{print $2}' <<<"${entry}")"
  selected_wallpaper="$(awk -F ':::' '{print $1}' <<<"${entry}")"
  export selected_wallpaper selected_wallpaper_path selected_thumbnail
  if [ -z "${selected_wallpaper}" ]; then
    print_log -err "wallpaper" " No wallpaper selected"
    exit 0
  fi
}

Wall_Hash() {
  # * Method to load wallpapers in hashmaps and fix broken links per theme
  setIndex=0
  [ ! -d "${HYPR_THEME_DIR}" ] && echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist" && exit 0
  wallPathArray=("${HYPR_THEME_DIR}/wallpapers")
  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")
  get_hashmap "${wallPathArray[@]}"
  [ ! -e "$(readlink -f "${wallSet}")" ] && echo "fixing link :: ${wallSet}" && ln -fs "${wallList[setIndex]}" "${wallSet}"
}

main() {
  #// set full cache variables
  if [ -z "$wallpaper_backend" ] \
    && [ "$wallpaper_setter_flag" != "o" ] \
    && [ "$wallpaper_setter_flag" != "g" ] \
    && [ "$wallpaper_setter_flag" != "select" ] \
    && [ "$wallpaper_setter_flag" != "start" ]; then
    print_log -sec "wallpaper" -err "No backend specified"
    print_log -sec "wallpaper" " Please specify a backend, try '--backend swww'"
    print_log -sec "wallpaper" " See available commands: '--help | -h'"
    exit 1
  fi

  # * --global flag is used to set the wallpaper as global, this means caching the wallpaper to thumbnails
  #  If wallpaper is used for thumbnails, set the following variables
  if [ "$set_as_global" == "true" ]; then
    mkdir -p "${WALLPAPER_CURRENT_DIR}"
    wallSet="${HYPR_THEME_DIR}/wall.set"
    wallCur="${WALLPAPER_CURRENT_DIR}/wall.set"
    wallSqr="${WALLPAPER_CURRENT_DIR}/wall.sqre"
    wallTmb="${WALLPAPER_CURRENT_DIR}/wall.thmb"
    wallBlr="${WALLPAPER_CURRENT_DIR}/wall.blur"
    wallQad="${WALLPAPER_CURRENT_DIR}/wall.quad"
  elif [ -n "${wallpaper_backend}" ]; then
    mkdir -p "${WALLPAPER_CURRENT_DIR}"
    wallCur="${WALLPAPER_CURRENT_DIR}/${wallpaper_backend}.png"
    wallSet="${HYPR_THEME_DIR}/wall.${wallpaper_backend}.png"
  else
    wallSet="${HYPR_THEME_DIR}/wall.set"
  fi

  # Ensure wallSet exists before applying
  if [ ! -e "${wallSet}" ]; then
    Wall_Hash
  fi

  if [ -n "${wallpaper_setter_flag}" ]; then
    export WALLPAPER_SET_FLAG="${wallpaper_setter_flag}"
    case "${wallpaper_setter_flag}" in
      n)
        Wall_Hash
        Wall_Change n
        ;;
      p)
        Wall_Hash
        Wall_Change p
        ;;
      r)
        Wall_Hash
        setIndex=$((RANDOM % ${#wallList[@]}))
        Wall_Cache "${wallList[setIndex]}"
        ;;
      s)
        if [ -z "${wallpaper_path}" ] || [ ! -f "${wallpaper_path}" ]; then
          print_log -err "wallpaper" "Wallpaper not found: ${wallpaper_path}"
          exit 1
        fi
        get_hashmap "${wallpaper_path}"
        Wall_Cache
        ;;
      start)
        # Start/apply current wallpaper to backend
        if [ ! -e "${wallSet}" ]; then
          print_log -err "wallpaper" "No current wallpaper found: ${wallSet}"
          exit 1
        fi
        export WALLPAPER_RELOAD_ALL=0 PYWAL_STARTUP=1
        current_wallpaper="$(realpath "${wallSet}")"
        get_hashmap "${current_wallpaper}"
        Wall_Cache
        ;;
      g)
        if [ ! -e "${wallSet}" ]; then
          print_log -err "wallpaper" "Wallpaper not found: ${wallSet}"
          exit 1
        fi
        realpath "${wallSet}"
        exit 0
        ;;
      o)
        if [ -n "${wallpaper_output}" ]; then
          print_log -sec "wallpaper" "Current wallpaper copied to: ${wallpaper_output}"
          cp -f "${wallSet}" "${wallpaper_output}"
        fi
        ;;
      select)
        Wall_Select
        get_hashmap "${selected_wallpaper_path}"
        Wall_Cache
        ;;
      link)
        Wall_Hash
        Wall_Cache
        exit 0
        ;;
    esac
  fi

  # Apply wallpaper to  backend
  if [ -f "${LIB_DIR}/hypr/wallpaper/wallpaper.${wallpaper_backend}.sh" ] && [ -n "${wallpaper_backend}" ]; then
    print_log -sec "wallpaper" "Using backend: ${wallpaper_backend}"
    "${LIB_DIR}/hypr/wallpaper/wallpaper.${wallpaper_backend}.sh" "${wallSet}"
  else
    if command -v "wallpaper.${wallpaper_backend}.sh" >/dev/null; then
      "wallpaper.${wallpaper_backend}.sh" "${wallSet}"
    else
      print_log -warn "wallpaper" "No backend script found for ${wallpaper_backend}"
      print_log -warn "wallpaper" "Created: $WALLPAPER_CURRENT_DIR/${wallpaper_backend}.png instead"
    fi
  fi

  if [ "${wallpaper_setter_flag}" == "select" ]; then
    if [ -e "$(readlink -f "${wallSet}")" ]; then
      if [ "${set_as_global}" == "true" ]; then
        notify-send -a "Wallpaper" -i "${selected_thumbnail}" "${selected_wallpaper}"
      else
        notify-send -a "Wallpaper" -i "${selected_thumbnail}" "${selected_wallpaper} set for ${wallpaper_backend}"
      fi
    else
      notify-send -a "Wallpaper" "Wallpaper not found"
    fi
  fi
}

#// evaluate options

if [ -z "${*}" ]; then
  echo "No arguments provided"
  show_help
fi

# Define long options
LONGOPTS="link,global,select,json,next,previous,random,set:,start,backend:,get,output:,help,filetypes:"

# Parse options
if ! PARSED=$(getopt --options GSjnprb:s:t:go:h --longoptions "$LONGOPTS" --name "$0" -- "$@"); then
  exit 2
fi

# Initialize the array for filetypes
WALLPAPER_OVERRIDE_FILETYPES=()

wallpaper_backend="${WALLPAPER_BACKEND:-swww}"
wallpaper_setter_flag=""
# Apply parsed options
eval set -- "$PARSED"
while true; do
  case "$1" in
    -G | --global)
      set_as_global=true
      shift
      ;;
    --link)
      wallpaper_setter_flag="link"
      shift
      ;;
    -j | --json)
      Wall_Json
      exit 0
      ;;
    -S | --select)
      "${LIB_DIR}/hypr/wallpaper/swwwallcache.sh" w &>/dev/null &
      wallpaper_setter_flag=select
      shift
      ;;
    -n | --next)
      wallpaper_setter_flag=n
      shift
      ;;
    -p | --previous)
      wallpaper_setter_flag=p
      shift
      ;;
    -r | --random)
      wallpaper_setter_flag=r
      shift
      ;;
    -s | --set)
      wallpaper_setter_flag=s
      wallpaper_path="${2}"
      shift 2
      ;;
    --start)
      wallpaper_setter_flag=start
      shift
      ;;
    -g | --get)
      wallpaper_setter_flag=g
      shift
      ;;
    -b | --backend)
      # Set wallpaper backend to use (swww, hyprpaper, etc.)
      wallpaper_backend="${2:-"$WALLPAPER_BACKEND"}"
      shift 2
      ;;
    -o | --output)
      # Accepts wallpaper output path
      wallpaper_setter_flag=o
      wallpaper_output="${2}"
      shift 2
      ;;
    -t | --filetypes)
      IFS=':' read -r -a WALLPAPER_OVERRIDE_FILETYPES <<<"$2"
      if [ "${LOG_LEVEL}" == "debug" ]; then
        for i in "${WALLPAPER_OVERRIDE_FILETYPES[@]}"; do
          print_log -g "DEBUG:" -b "filetype overrides : " "'${i}'"
        done
      fi
      export WALLPAPER_OVERRIDE_FILETYPES
      shift 2
      ;;
    -h | --help)
      show_help
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option: $1"
      echo "Try '$(basename "$0") --help' for more information."
      exit 1
      ;;
  esac
done

main
