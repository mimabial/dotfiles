#!/usr/bin/env bash
# shellcheck disable=SC2154

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
  # Recalculate HYPR_THEME_DIR after reloading config
  # (export_hypr_config only sources staterc, doesn't update derived paths)
  HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
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
        --clean-thumbs        Remove cached thumbs with no matching wallpapers


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
  local wallpaper_async="${WALLPAPER_ASYNC:-1}"
  local apply_colors=1

  case "${wallpaper_async,,}" in
    1 | true | yes | on) wallpaper_async=1 ;;
    0 | false | no | off) wallpaper_async=0 ;;
    *) wallpaper_async=1 ;;
  esac

  if [[ "${WALLPAPER_SKIP_COLORS:-0}" -eq 1 ]] || [[ "${enableWallDcol:-1}" -eq 0 ]]; then
    apply_colors=0
  fi

  # Experimental, set to 1 if stable
  if [[ "${WALLPAPER_RELOAD_ALL:-1}" -eq 1 ]] && [[ ${wallpaper_setter_flag} != "link" ]]; then
    print_log -sec "wallpaper" "Reloading themes and wallpapers"
    export reload_flag=1
  fi

  ln -fs "${wallList[setIndex]}" "${wallSet}"
  ln -fs "${wallList[setIndex]}" "${wallCur}"

  # Update hyprlock background
  command -v hyprlock.sh &>/dev/null && hyprlock.sh --background 202>&- &

  if [ "${set_as_global}" == "true" ]; then
    print_log -sec "wallpaper" "Setting Wallpaper as global"
    if [[ "${wallpaper_async}" -eq 1 ]]; then
      "${LIB_DIR}/hypr/wallpaper/swwwallcache.sh" -w "${wallList[setIndex]}" &>/dev/null 202>&- &
      if [[ "${apply_colors}" -eq 1 ]]; then
        {
          HYPR_WAL_ASYNC_APPS=1 "${LIB_DIR}/hypr/theme/color.set.sh" "${wallList[setIndex]}" &>/dev/null
          # Sync nvim after colors are generated
          [[ -x "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" ]] && "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" >/dev/null 2>&1
        } 202>&- &
      fi
    else
      "${LIB_DIR}/hypr/wallpaper/swwwallcache.sh" -w "${wallList[setIndex]}" &>/dev/null
      if [[ "${apply_colors}" -eq 1 ]]; then
        "${LIB_DIR}/hypr/theme/color.set.sh" "${wallList[setIndex]}"
        # Sync nvim after colors are generated
        [[ -x "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" ]] && "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" >/dev/null 2>&1 202>&- &
      fi
    fi
    if [[ -n "${wallList[setIndex]:-}" ]] && [[ -z "${wallHash[setIndex]:-}" ]]; then
      wallHash[setIndex]="$(set_hash "${wallList[setIndex]}")"
    fi
    if [[ -n "${wallHash[setIndex]:-}" ]]; then
      ln -fs "${thmbDir}/${wallHash[setIndex]}.sqre" "${wallSqr}"
      ln -fs "${thmbDir}/${wallHash[setIndex]}.thmb" "${wallTmb}"
      ln -fs "${thmbDir}/${wallHash[setIndex]}.blur" "${wallBlr}"
      ln -fs "${thmbDir}/${wallHash[setIndex]}.quad" "${wallQad}"
    else
      print_log -warn "wallpaper" "missing hash for ${wallList[setIndex]:-unknown}"
    fi
    rm -f "${WALLPAPER_CURRENT_DIR}/wall.fit"
  fi

  Wall_Auto_Prune
}

Wall_Change() {
  local curWall found
  found=false
  curWall="$(
    readlink -f -- "${wallSet}" 2>/dev/null \
      || realpath -- "${wallSet}" 2>/dev/null \
      || printf '%s' "${wallSet}"
  )"
  for i in "${!wallList[@]}"; do
    if [[ "${curWall}" == "${wallList[i]}" ]]; then
      found=true
      if [[ "${1}" == "n" ]]; then
        setIndex=$(((i + 1) % ${#wallList[@]}))
      elif [[ "${1}" == "p" ]]; then
        setIndex=$(((i - 1 + ${#wallList[@]}) % ${#wallList[@]}))
      fi
      break
    fi
  done
  if [[ "${found}" != true ]]; then
    setIndex=0
  fi
  Wall_Cache "${wallList[setIndex]}"
}

Wall_Hashmap_Cached() {
  unset wallHash wallList

  local -a wall_sources=()
  local skip_strays=0
  local no_notify=0
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --skipstrays) skip_strays=1 ;;
      --no-notify) no_notify=1 ;;
      *) wall_sources+=("${arg}") ;;
    esac
  done
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
  local cache_meta_file="${cache_file}.meta"
  mkdir -p "${cache_dir}"

  if [[ ${#wall_sources[@]} -eq 0 ]]; then
    get_hashmap "${wall_sources[@]}"
    return 0
  fi

  local -a get_hashmap_args=("${wall_sources[@]}")
  [[ "${no_notify}" -eq 1 ]] && get_hashmap_args+=(--no-notify)
  [[ "${skip_strays}" -eq 1 ]] && get_hashmap_args+=(--skipstrays)

  local meta_tmp="${cache_meta_file}.tmp"
  {
    printf 'created=%s\n' "$(date +%s)"
    local src resolved
    for src in "${wall_sources[@]}"; do
      [[ -n "${src}" ]] || continue
      [[ -e "${src}" ]] || continue
      resolved="$(
        readlink -f -- "${src}" 2>/dev/null \
          || realpath -- "${src}" 2>/dev/null \
          || printf '%s' "${src}"
      )"
      printf 'source=%s\n' "${resolved}"
    done
    local ext
    for ext in "${supported_files[@]}"; do
      [[ -n "${ext}" ]] || continue
      printf 'ext=%s\n' "${ext}"
    done
  } >"${meta_tmp}" && mv -f "${meta_tmp}" "${cache_meta_file}"

  local -A cache_hash
  local -A cache_meta
  if [[ -f "${cache_file}" ]]; then
    while IFS=$'\t' read -r hash mtime size path; do
      [[ -n "${path}" ]] || continue
      cache_hash["${path}"]="${hash}"
      cache_meta["${path}"]="${mtime}"$'\t'"${size}"
    done <"${cache_file}"
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
  : >"${tmp_cache}"

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
    printf '%s\t%s\t%s\n' "${wall_hash}" "${wall_meta}" "${wall_file}" >>"${tmp_cache}"
  done < <(
    find -H "${wall_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" -print0 2>/dev/null | sort -z
  )

  if [[ ${#wallList[@]} -eq 0 ]]; then
    rm -f "${tmp_cache}"
    get_hashmap "${get_hashmap_args[@]}"
    if [[ ${#wallList[@]} -gt 0 ]]; then
      tmp_cache="${cache_file}.tmp"
      : >"${tmp_cache}"
      local i
      for i in "${!wallList[@]}"; do
        wall_meta="$(stat -c '%Y\t%s' -- "${wallList[i]}" 2>/dev/null)" || continue
        printf '%s\t%s\t%s\n' "${wallHash[i]}" "${wall_meta}" "${wallList[i]}" >>"${tmp_cache}"
      done
      mv -f "${tmp_cache}" "${cache_file}"
    fi
    return 0
  fi

  mv -f "${tmp_cache}" "${cache_file}"
}

Wall_Ensure_Thumbs() {
  local ext="${1}"
  [[ -z "${ext}" ]] && ext="sqre"
  local -a missing_walls=()
  local thumb hash i
  local sync_limit="${WALLPAPER_THUMBS_SYNC_LIMIT:-3}"
  local sync_mode="${WALLPAPER_THUMBS_SYNC:-}"
  local run_async=1

  [[ "${sync_limit}" =~ ^[0-9]+$ ]] || sync_limit=3
  case "${sync_mode,,}" in
    1 | true | yes | on) run_async=0 ;;
    0 | false | no | off | "") run_async=1 ;;
  esac

  for i in "${!wallList[@]}"; do
    hash="${wallHash[i]}"
    if [[ -z "${hash}" ]]; then
      hash="$(set_hash "${wallList[i]}")"
      wallHash[i]="${hash}"
    fi
    [[ -n "${hash}" ]] || continue
    thumb="${thmbDir}/${hash}.${ext}"
    [[ -e "${thumb}" ]] || missing_walls+=("${wallList[i]}")
  done

  if ((${#missing_walls[@]} > 0)); then
    if [[ "${run_async}" -eq 0 ]] && [[ "${sync_limit}" -eq 0 ]]; then
      run_async=1
    fi
    if [[ "${run_async}" -eq 0 ]] && [[ "${sync_limit}" -gt 0 ]] && ((${#missing_walls[@]} > sync_limit)); then
      run_async=1
    fi
    local -a cache_args=()
    for wall in "${missing_walls[@]}"; do
      cache_args+=(-w "${wall}")
    done
    if [[ "${run_async}" -eq 1 ]]; then
      "${LIB_DIR}/hypr/wallpaper/swwwallcache.sh" "${cache_args[@]}" &>/dev/null &
    else
      "${LIB_DIR}/hypr/wallpaper/swwwallcache.sh" "${cache_args[@]}" &>/dev/null
    fi
  fi
}

Wall_Precache_Thumbs() {
  local lib_dir="${LIB_DIR}"
  local cache_script=""
  local theme_name="${HYPR_THEME}"

  [[ "${set_as_global}" == "true" ]] || return 0
  case "${wallpaper_setter_flag}" in
    "" | g | o | link) return 0 ;;
  esac
  [[ -z "${theme_name}" ]] && return 0

  [[ -z "${lib_dir}" ]] && lib_dir="${HOME}/.local/lib"
  cache_script="${lib_dir}/hypr/wallpaper/swwwallcache.sh"
  [[ -x "${cache_script}" ]] || return 0

  "${cache_script}" -t "${theme_name}" &>/dev/null &
}

Wall_Clean_Thumbs() {
  local thumb_dir="${thmbDir}"
  local cache_home="${HYPR_CACHE_HOME}"
  local config_home="${HYPR_CONFIG_HOME}"
  local runtime_dir="${XDG_RUNTIME_DIR}"
  local themes_root=""
  local lock_file=""
  local removed=0
  local file base hash
  local -a wall_sources=()
  local -A valid_hashes=()

  [[ -z "${runtime_dir}" ]] && runtime_dir="/run/user/$(id -u)"
  lock_file="${runtime_dir}/wallpaper-cache.lock"

  [[ -z "${cache_home}" ]] && cache_home="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
  [[ -z "${thumb_dir}" ]] && thumb_dir="${cache_home}/wallpaper/thumbs"
  [[ -d "${thumb_dir}" ]] || return 0

  [[ -z "${config_home}" ]] && config_home="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
  themes_root="${config_home}/themes"
  if [[ -d "${themes_root}" ]]; then
    wall_sources+=("${themes_root}")
  fi
  if [[ ${#WALLPAPER_CUSTOM_PATHS[@]} -gt 0 ]]; then
    local src
    for src in "${WALLPAPER_CUSTOM_PATHS[@]}"; do
      [[ -e "${src}" ]] || continue
      wall_sources+=("${src}")
    done
  fi
  [[ ${#wall_sources[@]} -gt 0 ]] || return 0

  exec 204>"${lock_file}"
  if ! flock -n 204; then
    flock 204
  fi

  if ! Wall_Hashmap_Cached "${wall_sources[@]}" --no-notify --skipstrays; then
    flock -u 204 2>/dev/null
    exec 204>&-
    return 0
  fi

  if [[ ${#wallList[@]} -eq 0 ]]; then
    flock -u 204 2>/dev/null
    exec 204>&-
    return 0
  fi

  for hash in "${wallHash[@]}"; do
    [[ -n "${hash}" ]] || continue
    valid_hashes["${hash}"]=1
  done

  while IFS= read -r -d '' file; do
    base="$(basename "${file}")"
    if [[ "${base}" =~ ^\.?([0-9a-fA-F]+)\.(thmb|sqre|blur|quad)(\.png)?$ ]]; then
      hash="${BASH_REMATCH[1]}"
      if [[ -z "${valid_hashes["${hash}"]}" ]]; then
        rm -f -- "${file}"
        removed=$((removed + 1))
      fi
    fi
  done < <(find -H "${thumb_dir}" -maxdepth 1 -type f -print0 2>/dev/null)

  flock -u 204 2>/dev/null
  exec 204>&-

  if [[ "${removed}" -gt 0 ]]; then
    print_log -sec "wallpaper" -stat "clean" "Removed ${removed} stale thumbs"
  fi
}

Wall_Prune_Hashmap_Caches() {
  local cache_root="${WALLPAPER_CACHE_DIR}"
  [[ -z "${cache_root}" ]] && cache_root="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/wallpaper"
  local cache_dir="${cache_root}/hashmap"
  [[ -d "${cache_dir}" ]] || return 0

  local ttl="${WALLPAPER_HASHMAP_PRUNE_TTL:-2592000}"
  [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl=2592000
  local now
  now="$(date +%s)"

  local file meta line src source_found mtime age
  while IFS= read -r -d '' file; do
    meta="${file}.meta"
    if [[ -f "${meta}" ]]; then
      source_found=0
      while IFS= read -r line; do
        case "${line}" in
          source=*)
            src="${line#source=}"
            if [[ -n "${src}" ]] && [[ -e "${src}" ]]; then
              source_found=1
              break
            fi
            ;;
        esac
      done <"${meta}"

      if [[ "${source_found}" -eq 0 ]]; then
        rm -f -- "${file}" "${meta}"
        continue
      fi

      if [[ "${ttl}" -gt 0 ]]; then
        mtime="$(stat -c %Y "${meta}" 2>/dev/null || stat -c %Y "${file}" 2>/dev/null || echo 0)"
        [[ "${mtime}" =~ ^[0-9]+$ ]] || mtime=0
        age=$((now - mtime))
        if (( age > ttl )); then
          rm -f -- "${file}" "${meta}"
        fi
      fi
    else
      if [[ "${ttl}" -gt 0 ]]; then
        mtime="$(stat -c %Y "${file}" 2>/dev/null || echo 0)"
        [[ "${mtime}" =~ ^[0-9]+$ ]] || mtime=0
        age=$((now - mtime))
        if (( age > ttl )); then
          rm -f -- "${file}"
        fi
      fi
    fi
  done < <(find -H "${cache_dir}" -maxdepth 1 -type f -name "*.tsv" -print0 2>/dev/null)
}

Wall_Auto_Prune() {
  local enabled="${WALLPAPER_AUTO_PRUNE:-1}"
  case "${enabled,,}" in
    1 | true | yes | on) enabled=1 ;;
    0 | false | no | off) enabled=0 ;;
    *) enabled=1 ;;
  esac
  [[ "${enabled}" -eq 1 ]] || return 0

  local ttl="${WALLPAPER_AUTO_PRUNE_TTL:-21600}"
  [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl=21600

  local cache_root="${WALLPAPER_CACHE_DIR}"
  [[ -z "${cache_root}" ]] && cache_root="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/wallpaper"
  local stamp_file="${cache_root}/.auto_prune.ts"
  mkdir -p "$(dirname "${stamp_file}")"

  local now last
  now="$(date +%s)"
  last=0
  if [[ -f "${stamp_file}" ]]; then
    last="$(cat "${stamp_file}" 2>/dev/null)"
    [[ "${last}" =~ ^[0-9]+$ ]] || last=0
  fi
  if [[ "${ttl}" -gt 0 ]] && (( now - last < ttl )); then
    return 0
  fi

  (
    exec 200>&- 201>&- 202>&- 203>&-
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-auto-prune.lock"
    exec 205>"${lock_file}"
    flock -n 205 || exit 0

    local now_ts last_ts
    now_ts="$(date +%s)"
    last_ts=0
    if [[ -f "${stamp_file}" ]]; then
      last_ts="$(cat "${stamp_file}" 2>/dev/null)"
      [[ "${last_ts}" =~ ^[0-9]+$ ]] || last_ts=0
    fi
    if [[ "${ttl}" -gt 0 ]] && (( now_ts - last_ts < ttl )); then
      exit 0
    fi

    printf '%s\n' "${now_ts}" > "${stamp_file}.tmp" && mv -f "${stamp_file}.tmp" "${stamp_file}"
    Wall_Clean_Thumbs --no-notify --skipstrays
    Wall_Prune_Hashmap_Caches
  ) &
  disown
}

# * Method to list wallpapers from hashmaps into json
Wall_Json() {
  local ensure_thumbs=0
  if [[ "${1}" == "--ensure-thumbs" ]]; then
    ensure_thumbs=1
    shift
  fi
  setIndex=0
  [ ! -d "${HYPR_THEME_DIR}" ] && echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist" && exit 0
  if [ -d "${HYPR_THEME_DIR}/wallpapers" ]; then
    wallPathArray=("${HYPR_THEME_DIR}/wallpapers")
  else
    wallPathArray=("${HYPR_THEME_DIR}")
  fi
  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")

  Wall_Hashmap_Cached "${wallPathArray[@]}" # get the hashmap provides wallList and wallHash
  if [[ "${ensure_thumbs}" -eq 1 ]]; then
    Wall_Ensure_Thumbs "sqre"
  fi

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
  # Exit early if rofi was cancelled
  [[ -z "${entry}" ]] && exit 0
  selected_thumbnail="$(awk -F ':::' '{print $3}' <<<"${entry}")"
  selected_wallpaper_path="$(awk -F ':::' '{print $2}' <<<"${entry}")"
  selected_wallpaper="$(awk -F ':::' '{print $1}' <<<"${entry}")"
  export selected_wallpaper selected_wallpaper_path selected_thumbnail
  if [ -z "${selected_wallpaper}" ]; then
    print_log -err "wallpaper" " No wallpaper selected"
    exit 0
  fi
}

Wall_List() {
  unset wallHash wallList

  local -a wall_sources=("$@")
  local -a supported_files=("gif" "jpg" "jpeg" "png" "${WALLPAPER_FILETYPES[@]}")
  if [[ ${#WALLPAPER_OVERRIDE_FILETYPES[@]} -gt 0 ]]; then
    supported_files=("${WALLPAPER_OVERRIDE_FILETYPES[@]}")
  fi

  local -a find_sources=()
  local src resolved
  for src in "${wall_sources[@]}"; do
    [[ -n "${src}" ]] || continue
    [[ -e "${src}" ]] || continue
    resolved="$(
      readlink -f -- "${src}" 2>/dev/null \
        || realpath -- "${src}" 2>/dev/null \
        || printf '%s' "${src}"
    )"
    find_sources+=("${resolved}")
  done
  [[ ${#find_sources[@]} -eq 0 ]] && return 1

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

  local wall_file
  while IFS= read -r -d '' wall_file; do
    wallList+=("${wall_file}")
  done < <(
    find -H "${find_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" -print0 2>/dev/null | sort -z
  )

  [[ ${#wallList[@]} -gt 0 ]]
}

Wall_Hash() {
  # * Method to load wallpapers in hashmaps and fix broken links per theme
  # Skip if already loaded (avoid redundant get_hashmap calls)
  [[ ${#wallList[@]} -gt 0 ]] && return 0
  setIndex=0
  [ ! -d "${HYPR_THEME_DIR}" ] && echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist" && exit 0
  wallPathArray=("${HYPR_THEME_DIR}/wallpapers")
  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")
  if ! Wall_List "${wallPathArray[@]}"; then
    print_log -err "wallpaper" "No compatible wallpapers found in theme paths"
    exit 1
  fi
  [ ! -e "$(readlink -f "${wallSet}")" ] && echo "fixing link :: ${wallSet}" && ln -fs "${wallList[setIndex]}" "${wallSet}"
}

main() {
  #// set full cache variables
  if [ -z "$wallpaper_backend" ] \
    && [ "$wallpaper_setter_flag" != "o" ] \
    && [ "$wallpaper_setter_flag" != "g" ] \
    && [ "$wallpaper_setter_flag" != "select" ] \
    && [ "$wallpaper_setter_flag" != "start" ] \
    && [ "$wallpaper_setter_flag" != "clean" ]; then
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
      clean)
        Wall_Clean_Thumbs
        exit 0
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

  Wall_Precache_Thumbs
}

#// evaluate options

if [ -z "${*}" ]; then
  echo "No arguments provided"
  show_help
fi

# Define long options
LONGOPTS="link,global,select,json,clean-thumbs,next,previous,random,set:,start,backend:,get,output:,help,filetypes:"

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
    --clean-thumbs)
      wallpaper_setter_flag=clean
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
