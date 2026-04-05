#!/usr/bin/env bash
# shellcheck disable=SC2154

# shellcheck source=/dev/null
source "$(command -v hyprshell)" || exit 1
export_hypr_config
# Recalculate HYPR_THEME_DIR after reloading config.
HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"

# Lock file to prevent concurrent wallpaper operations.
wallpaper_wait_for_lock="${WALLPAPER_WAIT_FOR_LOCK:-0}"
[[ "${wallpaper_wait_for_lock}" -ne 1 ]] && [[ " $* " == *" --wait-lock "* ]] && wallpaper_wait_for_lock=1
WALLPAPER_LOCK="$(hypr_lock_path wallpaper_switch)"
exec 202>"${WALLPAPER_LOCK}"
! flock -n 202 && {
  if [[ "${wallpaper_wait_for_lock}" -eq 1 ]]; then
    print_log -sec "wallpaper" -stat "wait" "Another wallpaper operation is already in progress"
    flock 202
  else
    print_log -sec "wallpaper" -stat "drop" "Another wallpaper operation is already in progress"
    exit 0
  fi
}
wallpaper_release_lock() {
  local exit_code="${1:-$?}"
  flock -u 202 2>/dev/null || true
  return "${exit_code}"
}
trap 'wallpaper_release_lock "$?"' EXIT

for wallpaper_lib in \
  wallpaper.common.bash \
  wallpaper.catalog.bash \
  wallpaper.thumbs.bash \
  wallpaper.actions.bash \
  wallpaper.ui.bash; do
  wallpaper_lib="${LIB_DIR}/hypr/wallpaper/lib/${wallpaper_lib}"
  if [[ ! -r "${wallpaper_lib}" ]]; then
    print_log -sec "wallpaper" -err "source" "missing ${wallpaper_lib}"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${wallpaper_lib}" || exit 1
done

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
  [[ -n "${wallpaper_backend}" ]] || return 0
  if [[ -f "${LIB_DIR}/hypr/wallpaper/wallpaper.${wallpaper_backend}.sh" ]]; then
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
    select | n | p | r | resume | s) return 0 ;;
    *) return 1 ;;
  esac
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

  notify_send_safe "${args[@]}" "$@"
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
  local notify_title="${notify_name}"

  [[ -n "${notify_icon}" ]] && notify_args+=(-i "${notify_icon}")
  [[ "${set_as_global}" == "true" ]] || notify_title="${notify_name} set for ${wallpaper_backend}"

  if [[ -n "${notify_body}" ]]; then
    wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_title}" "${notify_body}"
  else
    wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_title}"
  fi
}

wallpaper_refresh_inventory_if_needed() {
  case "${wallpaper_setter_flag:-}" in
    n | p | r) wallpaper_refresh_inventory_and_prune_async ;;
    g | o | clean | link | resume | s | start | select | "") return 0 ;;
    *) wallpaper_refresh_inventory_and_prune ;;
  esac
}

random_wallpaper_index() {
  local count="$1"
  local max_random=32768
  local accept_limit=0
  local candidate=0

  [[ "${count}" =~ ^[0-9]+$ ]] || return 1
  ((count > 0)) || return 1

  accept_limit=$((max_random - (max_random % count)))
  while :; do
    candidate=${RANDOM}
    if ((candidate < accept_limit)); then
      printf '%s\n' $((candidate % count))
      return 0
    fi
  done
}

require_wallpaper_backend() {
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
}

repair_active_wallpaper_link_if_needed() {
  if [[ -z "${wallpaper_setter_flag}" ]] && [[ ! -e "${active_wallpaper_link}" ]]; then
    Wall_Hash --repair-link
  fi
}

wallpaper_action_next() {
  Wall_Hash
  select_adjacent_wallpaper n
}

wallpaper_action_previous() {
  Wall_Hash
  select_adjacent_wallpaper p
}

wallpaper_action_random() {
  Wall_Hash
  setIndex="$(random_wallpaper_index "${#wallList[@]}")" || exit 1
  apply_selected_wallpaper "${wallList[setIndex]}"
}

wallpaper_action_set_file() {
  if [[ -z "${wallpaper_path}" ]] || [[ ! -f "${wallpaper_path}" ]]; then
    print_log -err "wallpaper" "Wallpaper not found: ${wallpaper_path}"
    exit 1
  fi
  get_hashmap "${wallpaper_path}" || exit 1
  apply_selected_wallpaper
}

wallpaper_action_resume() {
  local current_wallpaper=""
  local found=false
  local i=""

  Wall_Hash
  current_wallpaper="$(wallpaper_resolve_path "${active_wallpaper_link}")"
  for i in "${!wallList[@]}"; do
    if [[ "${current_wallpaper}" == "${wallList[i]}" ]]; then
      setIndex=$i
      found=true
      break
    fi
  done

  if [[ "${found}" != true ]]; then
    setIndex=0
    print_log -sec "wallpaper" -warn "wall.set not in current theme, using first wallpaper"
  fi

  apply_selected_wallpaper
}

wallpaper_action_start() {
  local current_wallpaper=""

  if [[ ! -e "${active_wallpaper_link}" ]]; then
    print_log -err "wallpaper" "No current wallpaper found: ${active_wallpaper_link}"
    exit 1
  fi

  export WALLPAPER_RELOAD_ALL=0 PYWAL_STARTUP=1
  current_wallpaper="$(realpath "${active_wallpaper_link}")"
  get_hashmap "${current_wallpaper}" || exit 1
  apply_selected_wallpaper
}

wallpaper_action_get() {
  if [[ ! -e "${active_wallpaper_link}" ]]; then
    print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"
    exit 1
  fi
  realpath "${active_wallpaper_link}"
  exit 0
}

wallpaper_action_output() {
  [[ -n "${wallpaper_output}" ]] || return 0
  print_log -sec "wallpaper" "Current wallpaper copied to: ${wallpaper_output}"
  cp -f "${active_wallpaper_link}" "${wallpaper_output}"
}

wallpaper_action_select() {
  Wall_Select
  get_hashmap "${selected_wallpaper_path}" || exit 1
  apply_selected_wallpaper
}

wallpaper_action_link() {
  Wall_Hash
  apply_selected_wallpaper
  exit 0
}

handle_wallpaper_action() {
  [[ -n "${wallpaper_setter_flag}" ]] || return 0

  export WALLPAPER_SET_FLAG="${wallpaper_setter_flag}"
  case "${wallpaper_setter_flag}" in
    n) wallpaper_action_next ;;
    p) wallpaper_action_previous ;;
    r) wallpaper_action_random ;;
    s) wallpaper_action_set_file ;;
    resume) wallpaper_action_resume ;;
    start) wallpaper_action_start ;;
    g) wallpaper_action_get ;;
    o) wallpaper_action_output ;;
    clean) Wall_Clean_Thumbs; exit 0 ;;
    select) wallpaper_action_select ;;
    link) wallpaper_action_link ;;
  esac
}

set_wallpaper_filetypes_override() {
  IFS=':' read -r -a WALLPAPER_OVERRIDE_FILETYPES <<<"$1"
  if [[ "${LOG_LEVEL}" == "debug" ]]; then
    for i in "${WALLPAPER_OVERRIDE_FILETYPES[@]}"; do
      print_log -g "DEBUG:" -b "filetype overrides : " "'${i}'"
    done
  fi
  export WALLPAPER_OVERRIDE_FILETYPES
}

wallpaper_set_action_flag() {
  wallpaper_setter_flag="$1"
  WALLPAPER_SHIFT=1
}

wallpaper_parse_immediate_option() {
  case "$1" in
    -j | --json)
      Wall_Json
      exit 0
      ;;
    -h | --help)
      show_help
      WALLPAPER_SHIFT=1
      return 0
      ;;
  esac

  return 1
}

wallpaper_parse_action_flag_option() {
  case "$1" in
    --clean-thumbs) wallpaper_set_action_flag clean ;;
    --link) wallpaper_set_action_flag link ;;
    -S | --select) wallpaper_set_action_flag select ;;
    -n | --next) wallpaper_set_action_flag n ;;
    -p | --previous) wallpaper_set_action_flag p ;;
    -r | --random) wallpaper_set_action_flag r ;;
    --resume) wallpaper_set_action_flag resume ;;
    --start) wallpaper_set_action_flag start ;;
    -g | --get) wallpaper_set_action_flag g ;;
    *) return 1 ;;
  esac

  return 0
}

wallpaper_parse_control_flag_option() {
  case "$1" in
    -G | --global)
      set_as_global=true
      WALLPAPER_SHIFT=1
      ;;
    --wait-lock)
      wallpaper_wait_for_lock=1
      WALLPAPER_SHIFT=1
      ;;
    --)
      WALLPAPER_SHIFT=-1
      ;;
    *) return 1 ;;
  esac

  return 0
}

wallpaper_parse_value_option() {
  case "$1" in
    -s | --set)
      wallpaper_setter_flag=s
      wallpaper_path="${2}"
      WALLPAPER_SHIFT=2
      ;;
    -b | --backend)
      wallpaper_backend="${2:-$WALLPAPER_BACKEND}"
      WALLPAPER_SHIFT=2
      ;;
    -o | --output)
      wallpaper_setter_flag=o
      wallpaper_output="${2}"
      WALLPAPER_SHIFT=2
      ;;
    -t | --filetypes)
      set_wallpaper_filetypes_override "$2"
      WALLPAPER_SHIFT=2
      ;;
    --notify-body)
      wallpaper_notify_body="${2}"
      WALLPAPER_SHIFT=2
      ;;
    *) return 1 ;;
  esac

  return 0
}

parse_wallpaper_option() {
  WALLPAPER_SHIFT=0
  wallpaper_parse_immediate_option "$1" && return 0
  wallpaper_parse_action_flag_option "$1" && return 0
  wallpaper_parse_control_flag_option "$1" && return 0
  wallpaper_parse_value_option "$1" "${2:-}" && return 0

  echo "Invalid option: $1"
  echo "Try '$(basename "$0") --help' for more information."
  exit 1
}

parse_wallpaper_args() {
  local parsed=""

  LONGOPTS="link,global,select,json,clean-thumbs,next,previous,random,resume,set:,start,backend:,get,output:,help,filetypes:,notify-body:,wait-lock"
  parsed="$(getopt --options GSjnprb:s:t:go:h --longoptions "${LONGOPTS}" --name "$0" -- "$@")" || exit 2

  WALLPAPER_OVERRIDE_FILETYPES=()
  wallpaper_backend="${WALLPAPER_BACKEND:-swww}"
  wallpaper_setter_flag=""
  set_as_global="${set_as_global:-false}"
  wallpaper_notify_body=""

  eval set -- "${parsed}"
  while true; do
    parse_wallpaper_option "$@"
    case "${WALLPAPER_SHIFT}" in
      -1)
        shift
        break
        ;;
      *)
        shift "${WALLPAPER_SHIFT}"
        ;;
    esac
  done
}

main() {
  require_wallpaper_backend

  wallpaper_set_paths
  wallpaper_refresh_inventory_if_needed
  repair_active_wallpaper_link_if_needed
  handle_wallpaper_action
  wallpaper_apply_backend
  Wall_Precache_Thumbs
  wallpaper_notify_result
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
fi

parse_wallpaper_args "$@"
main
