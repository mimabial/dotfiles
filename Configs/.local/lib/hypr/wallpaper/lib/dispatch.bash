#!/usr/bin/env bash

declare -gA WALLPAPER_ACTIONS=(
  [n]="wallpaper_action_next 1 1 1 1 async"
  [p]="wallpaper_action_previous 1 1 1 1 async"
  [r]="wallpaper_action_random 1 1 1 1 async"
  [s]="wallpaper_action_set 1 1 1 1 none"
  [resume]="wallpaper_action_resume 1 1 1 1 async"
  [display]="wallpaper_action_display 1 1 1 0 none"
  [notify]="wallpaper_action_notify 0 0 0 1 none"
  [select]="wallpaper_action_select 1 1 0 1 async"
  [start]="wallpaper_action_start 1 1 0 0 async"
  [link]="wallpaper_action_link 1 1 1 0 async"
  [g]="wallpaper_action_get 0 0 0 0 none"
  [o]="wallpaper_action_output 0 0 0 0 none"
  [clean]="wallpaper_action_clean 0 0 0 0 none"
  [json]="wallpaper_action_json 0 0 0 0 none"
)

wallpaper_resolve_action_profile() {
  local profile="${WALLPAPER_ACTIONS[${wallpaper_setter_flag}]-}"
  [[ -n "${profile}" ]] || {
    print_log -err "wallpaper" "Unknown action: ${wallpaper_setter_flag}"
    return 1
  }
  read -r wallpaper_action_handler wallpaper_action_wait_by_default \
    wallpaper_action_requires_lock wallpaper_action_requires_backend \
    wallpaper_action_notify wallpaper_inventory_refresh_mode <<<"${profile}"
  if [[ "${wallpaper_wait_for_lock}" -ne 1 ]] && [[ "${wallpaper_action_wait_by_default}" -eq 1 ]]; then
    wallpaper_wait_for_lock=1
  fi
}

wallpaper_acquire_lock_if_needed() {
  [[ "${wallpaper_action_requires_lock}" -eq 1 ]] || return 0

  local wallpaper_lock=""
  wallpaper_lock="$(hypr_lock_path wallpaper_switch)"
  exec {wallpaper_lock_fd}>"${wallpaper_lock}"

  if ! flock -n "${wallpaper_lock_fd}"; then
    if [[ "${wallpaper_wait_for_lock}" -eq 1 ]]; then
      print_log -sec "wallpaper" -stat "wait" "Another wallpaper operation is already in progress"
      flock "${wallpaper_lock_fd}"
    else
      print_log -sec "wallpaper" -stat "drop" "Another wallpaper operation is already in progress"
      exit 0
    fi
  fi
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

# An adapter is wallpaper.<backend>.sh, beside this library or on PATH, called with the
# active wallpaper link. It must display synchronously when WALLPAPER_WAIT_FOR_LOCK or
# WALLPAPER_SYNC_APPLY is 1, and exit non-zero on failure so the caller can warn.
wallpaper_apply_backend() {
  [[ "${WALLPAPER_SKIP_BACKEND_APPLY:-0}" -eq 1 ]] && return 0
  [[ -n "${wallpaper_backend}" ]] || return 0
  if [[ -f "${HYPR_LIB_DIR}/wallpaper/wallpaper.${wallpaper_backend}.sh" ]]; then
    print_log -sec "wallpaper" "Using backend: ${wallpaper_backend}"
    WALLPAPER_WAIT_FOR_LOCK="${wallpaper_wait_for_lock}" \
      "${HYPR_LIB_DIR}/wallpaper/wallpaper.${wallpaper_backend}.sh" "${active_wallpaper_link}"
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
  local elapsed_label=""

  # `notify` only re-displays the current wallpaper, so it applied nothing to time.
  if [[ -z "${notify_body}" && "${wallpaper_setter_flag}" != "notify" ]]; then
    if elapsed_label="$(hypr_elapsed_label "${wallpaper_started_ms:-}" 2>/dev/null)"; then
      notify_body="Time: ${elapsed_label}"
    fi
  fi

  [[ -n "${notify_icon}" ]] && notify_args+=(-i "${notify_icon}")
  [[ "${set_as_global}" == "true" ]] || notify_title="Wallpaper:${notify_name} (${wallpaper_backend})"

  if [[ -n "${notify_body}" ]]; then
    wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_title}" "${notify_body}"
  else
    wallpaper_notify_send 2000 "${notify_args[@]}" "${notify_title}"
  fi
}

wallpaper_refresh_inventory_if_needed() {
  [[ "${wallpaper_inventory_refresh_mode}" != async ]] || wallpaper_refresh_inventory_and_prune_async
}

random_wallpaper_index() {
  local count="$1"
  local max_random=1073741824
  local accept_limit=0
  local candidate=0

  [[ "${count}" =~ ^[0-9]+$ ]] || return 1
  ((count > 0 && count <= max_random)) || return 1

  accept_limit=$((max_random - (max_random % count)))
  while :; do
    candidate=$(((RANDOM << 15) | RANDOM))
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

wallpaper_select_current_or_first() {
  local missing_message="$1"
  local current_wallpaper="" index=""

  wallpaper_ensure_catalog
  current_wallpaper="$(wallpaper_resolve_path "${active_wallpaper_link}")"

  if index="$(catalog_index_of wallpaper_paths "${current_wallpaper}")"; then
    selected_wallpaper_index="${index}"
    return 0
  fi

  selected_wallpaper_index=0
  print_log -sec "wallpaper" -warn "${missing_message}"
}

handle_wallpaper_action() {
  export WALLPAPER_SET_FLAG="${wallpaper_setter_flag}"
  "${wallpaper_action_handler}"
}

wallpaper_action_next() { wallpaper_ensure_catalog; select_adjacent_wallpaper n; }
wallpaper_action_previous() { wallpaper_ensure_catalog; select_adjacent_wallpaper p; }
wallpaper_action_random() {
  wallpaper_ensure_catalog
  selected_wallpaper_index="$(random_wallpaper_index "${#wallpaper_paths[@]}")" || exit 1
  apply_selected_wallpaper
}
wallpaper_action_set() {
  [[ -f "${wallpaper_path}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${wallpaper_path}"; exit 1; }
  wallpaper_catalog_load_file "${wallpaper_path}" || exit 1
  apply_selected_wallpaper
}
wallpaper_action_resume() {
  wallpaper_select_current_or_first "wall.set not in current theme, using first wallpaper"
  apply_selected_wallpaper
}
wallpaper_action_display() {
  [[ -e "${active_wallpaper_link}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"; exit 1; }
  [[ "${set_as_global}" != true ]] || ln -fs "$(wallpaper_resolve_path "${active_wallpaper_link}")" "${current_wallpaper_link}"
}
wallpaper_action_notify() {
  wallpaper_select_current_or_first "wall.set not in current theme, using first wallpaper for notification"
  wallpaper_prepare_notification_payload "$(wallpaper_selected_path)"
  wallpaper_notify_result
  exit 0
}
wallpaper_action_start() {
  local current_wallpaper=""
  [[ -e "${active_wallpaper_link}" ]] || { print_log -err "wallpaper" "No current wallpaper found: ${active_wallpaper_link}"; exit 1; }
  export WALLPAPER_RELOAD_ALL=0
  current_wallpaper="$(realpath "${active_wallpaper_link}")"
  wallpaper_catalog_load_file "${current_wallpaper}" || exit 1
  apply_selected_wallpaper
}
wallpaper_action_get() {
  [[ -e "${active_wallpaper_link}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"; exit 1; }
  realpath "${active_wallpaper_link}"
  exit 0
}
wallpaper_action_output() {
  print_log -sec "wallpaper" "Current wallpaper copied to: ${wallpaper_output}"
  cp -f "${active_wallpaper_link}" "${wallpaper_output}"
}
wallpaper_action_clean() { wallpaper_clean_thumbs; exit 0; }
wallpaper_action_select() { wallpaper_pick; wallpaper_catalog_load_file "${selected_wallpaper_path}" || exit 1; apply_selected_wallpaper; }
wallpaper_action_link() { wallpaper_ensure_catalog; apply_selected_wallpaper; exit 0; }
wallpaper_action_json() { wallpaper_json; exit 0; }
