#!/usr/bin/env bash
# shellcheck disable=SC2154

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

declare -ga wallHash=()
declare -ga wallList=()
declare -ga wallPathArray=()

wallpaper_wait_for_lock="${WALLPAPER_WAIT_FOR_LOCK:-0}"
wallpaper_lock_acquired=0
wallpaper_action_wait_by_default=0
wallpaper_action_requires_lock=0
wallpaper_action_requires_backend=1
wallpaper_action_notify=0
wallpaper_notifications_disabled=0
wallpaper_inventory_refresh_mode="none"

wallpaper_release_lock() {
  local exit_code="${1:-$?}"
  if [[ "${wallpaper_lock_acquired}" -eq 1 ]]; then
    flock -u 202 2>/dev/null || true
  fi
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

wallpaper_resolve_action_profile() {
  wallpaper_action_wait_by_default=0
  wallpaper_action_requires_lock=0
  wallpaper_action_requires_backend=1
  wallpaper_action_notify=0
  wallpaper_inventory_refresh_mode="none"

  case "${wallpaper_setter_flag:-}" in
    n | p | r)
      wallpaper_action_wait_by_default=1
      wallpaper_action_requires_lock=1
      wallpaper_action_notify=1
      wallpaper_inventory_refresh_mode="async"
      ;;
    s)
      wallpaper_action_wait_by_default=1
      wallpaper_action_requires_lock=1
      wallpaper_action_notify=1
      ;;
    resume)
      wallpaper_action_wait_by_default=1
      wallpaper_action_requires_lock=1
      wallpaper_action_notify=1
      wallpaper_inventory_refresh_mode="async"
      ;;
    notify)
      wallpaper_action_requires_backend=0
      wallpaper_action_notify=1
      ;;
    select)
      wallpaper_action_wait_by_default=1
      wallpaper_action_requires_lock=1
      wallpaper_action_requires_backend=0
      wallpaper_action_notify=1
      wallpaper_inventory_refresh_mode="async"
      ;;
    start)
      wallpaper_action_wait_by_default=1
      wallpaper_action_requires_lock=1
      wallpaper_action_requires_backend=0
      wallpaper_inventory_refresh_mode="async"
      ;;
    link)
      wallpaper_action_wait_by_default=1
      wallpaper_action_requires_lock=1
      wallpaper_inventory_refresh_mode="async"
      ;;
    g | o | clean)
      wallpaper_action_requires_backend=0
      ;;
    "")
      ;;
    *)
      wallpaper_inventory_refresh_mode="sync"
      ;;
  esac
  if [[ "${wallpaper_wait_for_lock}" -ne 1 ]] && [[ "${wallpaper_action_wait_by_default}" -eq 1 ]]; then
    wallpaper_wait_for_lock=1
  fi
}

wallpaper_acquire_lock_if_needed() {
  [[ "${wallpaper_action_requires_lock}" -eq 1 ]] || return 0

  local wallpaper_lock=""
  wallpaper_lock="$(hypr_lock_path wallpaper_switch)"
  exec 202>"${wallpaper_lock}"

  if ! flock -n 202; then
    if [[ "${wallpaper_wait_for_lock}" -eq 1 ]]; then
      print_log -sec "wallpaper" -stat "wait" "Another wallpaper operation is already in progress"
      flock 202
    else
      print_log -sec "wallpaper" -stat "drop" "Another wallpaper operation is already in progress"
      exit 0
    fi
  fi

  wallpaper_lock_acquired=1
}

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
    WALLPAPER_WAIT_FOR_LOCK="${wallpaper_wait_for_lock}" \
      "${LIB_DIR}/hypr/wallpaper/wallpaper.${wallpaper_backend}.sh" "${active_wallpaper_link}"
    return
  fi

  if command -v "wallpaper.${wallpaper_backend}.sh" >/dev/null 2>&1; then
    WALLPAPER_WAIT_FOR_LOCK="${wallpaper_wait_for_lock}" \
      "wallpaper.${wallpaper_backend}.sh" "${active_wallpaper_link}"
  else
    print_log -warn "wallpaper" "No backend script found for ${wallpaper_backend}"
    print_log -warn "wallpaper" "Created: $WALLPAPER_CURRENT_DIR/${wallpaper_backend}.png instead"
  fi
}

wallpaper_action_emits_notification() {
  [[ "${wallpaper_notifications_disabled}" -ne 1 ]] || return 1
  [[ "${wallpaper_action_notify}" -eq 1 ]]
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

  notify_send_safe "${args[@]}" "$@" || true
  return 0
}

wallpaper_notify_result() {
  wallpaper_action_emits_notification || return 0

  if [[ ! -e "$(readlink -f "${active_wallpaper_link}")" ]]; then
    wallpaper_notify_send 3000 "Wallpaper not found"
    return
  fi

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
  case "${wallpaper_inventory_refresh_mode}" in
    async) wallpaper_refresh_inventory_and_prune_async ;;
    sync) wallpaper_refresh_inventory_and_prune ;;
    *) return 0 ;;
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
  if [[ -z "${wallpaper_backend}" ]] && [[ "${wallpaper_action_requires_backend}" -eq 1 ]]; then
    print_log -sec "wallpaper" -err "No backend specified"
    print_log -sec "wallpaper" " Please specify a backend, try '--backend awww'"
    print_log -sec "wallpaper" " See available commands: '--help | -h'"
    exit 1
  fi
}

repair_active_wallpaper_link_if_needed() {
  if [[ -z "${wallpaper_setter_flag}" ]] && [[ ! -e "${active_wallpaper_link}" ]]; then
    Wall_Hash --repair-link
  fi
}

wallpaper_select_current_or_first() {
  local missing_message="$1"
  local current_wallpaper=""
  local i=""

  Wall_Hash
  current_wallpaper="$(wallpaper_resolve_path "${active_wallpaper_link}")"
  for i in "${!wallList[@]}"; do
    if [[ "${current_wallpaper}" == "${wallList[i]}" ]]; then
      setIndex=$i
      return 0
    fi
  done

  setIndex=0
  print_log -sec "wallpaper" -warn "${missing_message}"
}

handle_wallpaper_action() {
  [[ -n "${wallpaper_setter_flag}" ]] || return 0

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
      setIndex="$(random_wallpaper_index "${#wallList[@]}")" || exit 1
      apply_selected_wallpaper "${wallList[setIndex]}"
      ;;
    s)
      if [[ -z "${wallpaper_path}" ]] || [[ ! -f "${wallpaper_path}" ]]; then
        print_log -err "wallpaper" "Wallpaper not found: ${wallpaper_path}"
        exit 1
      fi
      get_hashmap "${wallpaper_path}" || exit 1
      apply_selected_wallpaper
      ;;
    resume)
      wallpaper_select_current_or_first "wall.set not in current theme, using first wallpaper"
      apply_selected_wallpaper
      ;;
    notify)
      wallpaper_select_current_or_first "wall.set not in current theme, using first wallpaper for notification"
      wallpaper_prepare_notification_payload
      wallpaper_notify_result
      exit 0
      ;;
    start)
      local current_wallpaper=""

      if [[ ! -e "${active_wallpaper_link}" ]]; then
        print_log -err "wallpaper" "No current wallpaper found: ${active_wallpaper_link}"
        exit 1
      fi

      export WALLPAPER_RELOAD_ALL=0 PYWAL_STARTUP=1
      current_wallpaper="$(realpath "${active_wallpaper_link}")"
      get_hashmap "${current_wallpaper}" || exit 1
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
      [[ -n "${wallpaper_output}" ]] || return 0
      print_log -sec "wallpaper" "Current wallpaper copied to: ${wallpaper_output}"
      cp -f "${active_wallpaper_link}" "${wallpaper_output}"
      ;;
    clean) Wall_Clean_Thumbs; exit 0 ;;
    select)
      Wall_Select
      get_hashmap "${selected_wallpaper_path}" || exit 1
      apply_selected_wallpaper
      ;;
    link)
      Wall_Hash
      apply_selected_wallpaper
      exit 0
      ;;
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

wallpaper_parse_common_option() {
  WALLPAPER_SHIFT=0
  wallpaper_parse_control_flag_option "$1" && return 0
  wallpaper_parse_value_option "$1" "${2:-}" && return 0
  return 1
}

wallpaper_parse_action_flag_option() {
  case "$1" in
    --clean-thumbs) wallpaper_setter_flag=clean; WALLPAPER_SHIFT=1 ;;
    --link) wallpaper_setter_flag=link; WALLPAPER_SHIFT=1 ;;
    -S | --select) wallpaper_setter_flag=select; WALLPAPER_SHIFT=1 ;;
    -n | --next) wallpaper_setter_flag=n; WALLPAPER_SHIFT=1 ;;
    -p | --previous) wallpaper_setter_flag=p; WALLPAPER_SHIFT=1 ;;
    -r | --random) wallpaper_setter_flag=r; WALLPAPER_SHIFT=1 ;;
    --resume) wallpaper_setter_flag=resume; WALLPAPER_SHIFT=1 ;;
    --start) wallpaper_setter_flag=start; WALLPAPER_SHIFT=1 ;;
    -g | --get) wallpaper_setter_flag=g; WALLPAPER_SHIFT=1 ;;
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
    --no-notify)
      wallpaper_notifications_disabled=1
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

wallpaper_modern_command_token() {
  local command_name="${1:-}"

  WALLPAPER_SHIFT=0
  case "${command_name}" in
    help | --help | -h)
      show_help
      ;;
    next)
      wallpaper_setter_flag="n"
      WALLPAPER_SHIFT=1
      ;;
    previous | prev)
      wallpaper_setter_flag="p"
      WALLPAPER_SHIFT=1
      ;;
    random)
      wallpaper_setter_flag="r"
      WALLPAPER_SHIFT=1
      ;;
    select)
      wallpaper_setter_flag="select"
      WALLPAPER_SHIFT=1
      ;;
    resume)
      wallpaper_setter_flag="resume"
      WALLPAPER_SHIFT=1
      ;;
    notify)
      wallpaper_setter_flag="notify"
      WALLPAPER_SHIFT=1
      ;;
    start)
      wallpaper_setter_flag="start"
      WALLPAPER_SHIFT=1
      ;;
    get)
      wallpaper_setter_flag="g"
      WALLPAPER_SHIFT=1
      ;;
    link)
      wallpaper_setter_flag="link"
      WALLPAPER_SHIFT=1
      ;;
    clean)
      wallpaper_setter_flag="clean"
      WALLPAPER_SHIFT=1
      ;;
    json)
      Wall_Json
      exit 0
      ;;
    set)
      [[ -n "${2:-}" ]] || {
        echo "Error: set requires a file path." >&2
        exit 1
      }
      wallpaper_setter_flag="s"
      wallpaper_path="${2}"
      WALLPAPER_SHIFT=2
      ;;
    output)
      [[ -n "${2:-}" ]] || {
        echo "Error: output requires a file path." >&2
        exit 1
      }
      wallpaper_setter_flag="o"
      wallpaper_output="${2}"
      WALLPAPER_SHIFT=2
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

parse_wallpaper_args_modern() {
  local command_seen=0

  WALLPAPER_OVERRIDE_FILETYPES=()
  wallpaper_backend="${WALLPAPER_BACKEND:-awww}"
  wallpaper_setter_flag=""
  set_as_global="${set_as_global:-false}"
  wallpaper_notify_body=""
  wallpaper_notifications_disabled=0

  while (($#)); do
    if (( command_seen == 0 )) && wallpaper_parse_common_option "$1" "${2:-}"; then
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_modern_command_token "$1" "${2:-}"; then
      command_seen=1
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 1 )) && wallpaper_parse_common_option "$1" "${2:-}"; then
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    echo "Invalid wallpaper argument: $1" >&2
    echo "Try '$(basename "$0") --help' for more information." >&2
    exit 1
  done

  if (( command_seen == 0 )); then
    show_help
  fi
}

main() {
  require_wallpaper_backend
  wallpaper_acquire_lock_if_needed

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

parse_wallpaper_args_modern "$@"
wallpaper_resolve_action_profile
main
