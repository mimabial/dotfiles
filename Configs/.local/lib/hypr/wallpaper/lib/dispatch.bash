#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# dispatch.bash - Action policy and the action handler for wallpaper.sh.
#
# wallpaper_resolve_action_profile maps each action (set in
# wallpaper_setter_flag by the parsers) to five booleans + a refresh mode.
# Adding a new action means adding a row here as well as a branch in
# handle_wallpaper_action.
#
# Subsystem inputs (set by wallpaper.sh entrypoint or its parser):
#   wallpaper_setter_flag, wallpaper_path, wallpaper_backend,
#   wallpaper_output, wallpaper_notify_body, wallpaper_notifications_disabled,
#   set_as_global, wallList, wallHash, setIndex,
#   selected_wallpaper, selected_wallpaper_path, selected_thumbnail
# Subsystem outputs (consumed by wallpaper.sh and the other lib modules):
#   wallpaper_lock_acquired, active_wallpaper_link, current_wallpaper_link,
#   current_square_thumbnail_link, current_thumbnail_link,
#   current_blur_thumbnail_link, current_quad_thumbnail_link
: "${wallpaper_setter_flag-}" "${wallpaper_path-}" "${wallpaper_backend-}" \
  "${wallpaper_output-}" "${wallpaper_notify_body-}" \
  "${wallpaper_notifications_disabled-}" "${set_as_global-}" \
  "${wallList-}" "${wallHash-}" "${setIndex-}" \
  "${selected_wallpaper_path-}" \
  "${wallpaper_lock_acquired-}" "${active_wallpaper_link-}" \
  "${current_wallpaper_link-}" "${current_square_thumbnail_link-}" \
  "${current_thumbnail_link-}" "${current_blur_thumbnail_link-}" \
  "${current_quad_thumbnail_link-}"

# Initialize default. Action profile resolution overrides; --wait-lock
# forces it to 1; the env value seeds it for callers that want to opt in
# from outside (theme apply phase D).
wallpaper_wait_for_lock="${WALLPAPER_WAIT_FOR_LOCK:-0}"

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
    display)
      wallpaper_action_wait_by_default=1
      wallpaper_action_requires_lock=1
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
    "") ;;
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

# Backend adapter contract.
#
# An adapter is a script named wallpaper.<backend>.sh located at
# ${LIB_DIR}/hypr/wallpaper/ (or anywhere on PATH). When the user passes
# --backend <backend>, this function picks the script up and invokes it.
#
# Inputs:
#   $1                          - Path to the active wallpaper link
#                                 (active_wallpaper_link). Adapters resolve it
#                                 with `readlink -f` / wallpaper_resolve_path.
#
# Environment the adapter MAY read:
#   WALLPAPER_WAIT_FOR_LOCK     - 0|1; if 1, the adapter must apply the
#                                 wallpaper synchronously before returning.
#                                 Set by interactive actions to keep submits
#                                 ordered.
#   WALLPAPER_SET_FLAG          - n|p|r|s|select|resume|start|... — the action
#                                 that triggered this apply. Useful for
#                                 backend-specific transitions (awww uses it
#                                 to pick `next` vs `previous` transition).
#   WALLPAPER_SYNC_APPLY        - 0|1; alternate sync request used by the
#                                 theme.apply phase-D envelope so the
#                                 wallpaper child finishes before the cgroup
#                                 is torn down.
#   WALLPAPER_CURRENT_DIR       - Directory holding wall.set / wall.<backend>
#                                 link family.
#   HYPR_THEME_DIR              - Active theme directory; backends may use
#                                 this for theme-relative assets.
#   WALLPAPER_VIDEO_DIR         - Where to extract still frames when the
#                                 input is a video the backend can't display.
#
# Output / side effects:
#   The adapter is responsible for displaying the wallpaper via its native
#   IPC (awww img, hyprctl hyprpaper reload, mpvpaper exec, ...). It MUST
#   exit 0 on success. Errors should print via print_log -err and exit
#   non-zero so the caller can warn.
#
# Synchrony: when WALLPAPER_WAIT_FOR_LOCK=1 or WALLPAPER_SYNC_APPLY=1, the
# adapter must NOT background its display call. Otherwise it MAY background
# (awww does this for snappier interactive feel).
wallpaper_apply_backend() {
  [[ "${WALLPAPER_SKIP_BACKEND_APPLY:-0}" -eq 1 ]] && return 0
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
  local notify_title="Wallpaper: ${notify_name}"

  [[ -n "${notify_icon}" ]] && notify_args+=(-i "${notify_icon}")
  [[ "${set_as_global}" == "true" ]] || notify_title="Wallpaper:${notify_name} (${wallpaper_backend})"

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
    display)
      if [[ ! -e "${active_wallpaper_link}" ]]; then
        print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"
        exit 1
      fi
      if [[ "${set_as_global}" == "true" ]]; then
        ln -fs "$(wallpaper_resolve_path "${active_wallpaper_link}")" "${current_wallpaper_link}"
      fi
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
    clean)
      Wall_Clean_Thumbs
      exit 0
      ;;
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
