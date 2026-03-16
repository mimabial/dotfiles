#!/usr/bin/env bash
# shellcheck disable=SC2154
# shellcheck disable=SC1091

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
elif ! declare -F print_log >/dev/null 2>&1 || ! declare -F send_ephemeral_notif >/dev/null 2>&1; then
  if [[ -r "${LIB_DIR}/hypr/globalcontrol.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/hypr/globalcontrol.sh"
  fi
fi

if declare -F export_hypr_config >/dev/null 2>&1; then
  export_hypr_config
  # Recalculate HYPR_THEME_DIR after reloading config.
  HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
fi

# Lock file to prevent concurrent wallpaper operations.
WALLPAPER_LOCK="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-switch.lock"
exec 202>"${WALLPAPER_LOCK}"
! flock -n 202 && {
  print_log -sec "wallpaper" -stat "drop" "Another wallpaper operation is already in progress"
  exit 0
}
trap 'flock -u 202 2>/dev/null' EXIT

wallpaper_source_lib() {
  local lib_file="$1"
  if [[ ! -r "${lib_file}" ]]; then
    print_log -sec "wallpaper" -err "source" "missing ${lib_file}"
    return 1
  fi
  # shellcheck source=/dev/null
  source "${lib_file}"
}

wallpaper_source_lib "${LIB_DIR}/hypr/wallpaper/lib/wallpaper.common.bash" || exit 1
wallpaper_source_lib "${LIB_DIR}/hypr/wallpaper/lib/wallpaper.catalog.bash" || exit 1
wallpaper_source_lib "${LIB_DIR}/hypr/wallpaper/lib/wallpaper.thumbs.bash" || exit 1
wallpaper_source_lib "${LIB_DIR}/hypr/wallpaper/lib/wallpaper.actions.bash" || exit 1
wallpaper_source_lib "${LIB_DIR}/hypr/wallpaper/lib/wallpaper.ui.bash" || exit 1

wallpaper_set_paths() {
  if [[ "${set_as_global}" == "true" ]]; then
    mkdir -p "${WALLPAPER_CURRENT_DIR}"
    active_wallpaper_link="${HYPR_THEME_DIR}/wall.set"
    current_wallpaper_link="${WALLPAPER_CURRENT_DIR}/wall.set"
    current_square_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.sqre"
    current_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.thmb"
    current_blur_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.blur"
    current_quad_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.quad"
  elif [[ -n "${wallpaper_backend}" ]]; then
    mkdir -p "${WALLPAPER_CURRENT_DIR}"
    current_wallpaper_link="${WALLPAPER_CURRENT_DIR}/${wallpaper_backend}.png"
    active_wallpaper_link="${HYPR_THEME_DIR}/wall.${wallpaper_backend}.png"
  else
    active_wallpaper_link="${HYPR_THEME_DIR}/wall.set"
  fi
}

wallpaper_apply_backend() {
  if [[ -f "${LIB_DIR}/hypr/wallpaper/wallpaper.${wallpaper_backend}.sh" ]] && [[ -n "${wallpaper_backend}" ]]; then
    print_log -sec "wallpaper" "Using backend: ${wallpaper_backend}"
    "${LIB_DIR}/hypr/wallpaper/wallpaper.${wallpaper_backend}.sh" "${active_wallpaper_link}"
    return
  fi

  if command -v "wallpaper.${wallpaper_backend}.sh" >/dev/null 2>&1; then
    "wallpaper.${wallpaper_backend}.sh" "${active_wallpaper_link}"
  else
    print_log -warn "wallpaper" "No backend script found for ${wallpaper_backend}"
    print_log -warn "wallpaper" "Created: $WALLPAPER_CURRENT_DIR/${wallpaper_backend}.png instead"
  fi
}

wallpaper_action_emits_notification() {
  case "${wallpaper_setter_flag:-}" in
    select | n | p | r | s)
      return 0
      ;;
  esac
  return 1
}

wallpaper_notify_send() {
  local timeout_ms="$1"
  shift

  local replace_id="${WALLPAPER_NOTIFY_REPLACE_ID:-93}"
  local -a args=(
    -a "Wallpaper"
    -t "${timeout_ms}"
    -r "${replace_id}"
  )

  send_notifs "${args[@]}" "$@"
}

wallpaper_notify_result() {
  wallpaper_action_emits_notification || return 0

  if [[ ! -e "$(readlink -f "${active_wallpaper_link}")" ]]; then
    wallpaper_notify_send 3000 "Wallpaper not found"
    return
  fi

  wallpaper_should_apply_colors_async && return 0
  wallpaper_notify_emit
}

wallpaper_notify_emit() {
  local notify_name="${1:-${HYPR_WALLPAPER_NOTIFY_NAME:-${selected_wallpaper:-}}}"
  local notify_icon="${2:-${HYPR_WALLPAPER_NOTIFY_ICON:-${selected_thumbnail:-}}}"
  local notify_body="${3:-${wallpaper_notify_body:-}}"
  local -a notify_args=()

  [[ -n "${notify_icon}" ]] && notify_args+=(-i "${notify_icon}")

  if [[ "${set_as_global}" == "true" ]]; then
    if [[ -n "${notify_body}" ]]; then
      wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_name}" "${notify_body}"
    else
      wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_name}"
    fi
  else
    if [[ -n "${notify_body}" ]]; then
      wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_name} set for ${wallpaper_backend}" "${notify_body}"
    else
      wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_name} set for ${wallpaper_backend}"
    fi
  fi
}

main() {
  # Full cache variables are required for write/apply operations.
  if [[ -z "${wallpaper_backend}" ]] \
    && [[ "${wallpaper_setter_flag}" != "o" ]] \
    && [[ "${wallpaper_setter_flag}" != "g" ]] \
    && [[ "${wallpaper_setter_flag}" != "select" ]] \
    && [[ "${wallpaper_setter_flag}" != "start" ]] \
    && [[ "${wallpaper_setter_flag}" != "clean" ]]; then
    print_log -sec "wallpaper" -err "No backend specified"
    print_log -sec "wallpaper" " Please specify a backend, try '--backend swww'"
    print_log -sec "wallpaper" " See available commands: '--help | -h'"
    exit 1
  fi

  wallpaper_set_paths

  # Ensure active wallpaper link exists before applying.
  if [[ ! -e "${active_wallpaper_link}" ]]; then
    Wall_Hash
  fi

  if [[ -n "${wallpaper_setter_flag}" ]]; then
    export WALLPAPER_SET_FLAG="${wallpaper_setter_flag}"
    case "${wallpaper_setter_flag}" in
      n)
        Wall_Hash
        select_adjacent_wallpaper n
        ;;
      p)
        Wall_Hash
        select_adjacent_wallpaper p
        ;;
      r)
        Wall_Hash
        setIndex=$((RANDOM % ${#wallList[@]}))
        apply_selected_wallpaper "${wallList[setIndex]}"
        ;;
      s)
        if [[ -z "${wallpaper_path}" ]] || [[ ! -f "${wallpaper_path}" ]]; then
          print_log -err "wallpaper" "Wallpaper not found: ${wallpaper_path}"
          exit 1
        fi
        get_hashmap "${wallpaper_path}"
        apply_selected_wallpaper
        ;;
      start)
        if [[ ! -e "${active_wallpaper_link}" ]]; then
          print_log -err "wallpaper" "No current wallpaper found: ${active_wallpaper_link}"
          exit 1
        fi
        export WALLPAPER_RELOAD_ALL=0 PYWAL_STARTUP=1
        current_wallpaper="$(realpath "${active_wallpaper_link}")"
        get_hashmap "${current_wallpaper}"
        apply_selected_wallpaper
        ;;
      g)
        if [[ ! -e "${active_wallpaper_link}" ]]; then
          print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"
          exit 1
        fi
        realpath "${active_wallpaper_link}"
        exit 0
        ;;
      o)
        if [[ -n "${wallpaper_output}" ]]; then
          print_log -sec "wallpaper" "Current wallpaper copied to: ${wallpaper_output}"
          cp -f "${active_wallpaper_link}" "${wallpaper_output}"
        fi
        ;;
      clean)
        Wall_Clean_Thumbs
        exit 0
        ;;
      select)
        Wall_Select
        get_hashmap "${selected_wallpaper_path}"
        apply_selected_wallpaper
        ;;
      link)
        Wall_Hash
        apply_selected_wallpaper
        exit 0
        ;;
    esac
  fi

  wallpaper_apply_backend
  Wall_Precache_Thumbs
  wallpaper_notify_result
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
fi

LONGOPTS="link,global,select,json,clean-thumbs,next,previous,random,set:,start,backend:,get,output:,help,filetypes:,notify-body:"

if ! PARSED=$(getopt --options GSjnprb:s:t:go:h --longoptions "${LONGOPTS}" --name "$0" -- "$@"); then
  exit 2
fi

WALLPAPER_OVERRIDE_FILETYPES=()
wallpaper_backend="${WALLPAPER_BACKEND:-swww}"
wallpaper_setter_flag=""
set_as_global="${set_as_global:-false}"
wallpaper_notify_body=""

# Apply parsed options.
eval set -- "${PARSED}"
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
      wallpaper_backend="${2:-$WALLPAPER_BACKEND}"
      shift 2
      ;;
    -o | --output)
      wallpaper_setter_flag=o
      wallpaper_output="${2}"
      shift 2
      ;;
    -t | --filetypes)
      IFS=':' read -r -a WALLPAPER_OVERRIDE_FILETYPES <<<"$2"
      if [[ "${LOG_LEVEL}" == "debug" ]]; then
        for i in "${WALLPAPER_OVERRIDE_FILETYPES[@]}"; do
          print_log -g "DEBUG:" -b "filetype overrides : " "'${i}'"
        done
      fi
      export WALLPAPER_OVERRIDE_FILETYPES
      shift 2
      ;;
    --notify-body)
      wallpaper_notify_body="${2}"
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
