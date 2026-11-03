#!/usr/bin/env bash

wallpaper_prepare_notification_payload() {
  local wallpaper_path="${1:-}" wallpaper_hash=""
  if [[ -z "${wallpaper_path}" && -e "${active_wallpaper_link}" ]]; then
    wallpaper_path="$(wallpaper_resolve_path "${active_wallpaper_link}")"
  fi
  [[ -n "${wallpaper_path}" ]] || return 1
  wallpaper_ensure_hash wallpaper_hash_by_path "${wallpaper_path}" || return 1
  wallpaper_hash="${wallpaper_hash_by_path[${wallpaper_path}]}"
  export HYPR_WALLPAPER_NOTIFY_NAME="${wallpaper_path##*/}"
  export HYPR_WALLPAPER_NOTIFY_ICON="${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre"
}

wallpaper_action_emits_notification() {
  [[ "${wallpaper_notifications_disabled}" -ne 1 ]] || return 1
  wallpaper_policy_notifies "${wallpaper_action}"
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
    wallpaper_notify_send "${NOTIFY_MS}" "Wallpaper not found"
    return
  fi

  wallpaper_notify_emit
}

wallpaper_notify_emit() {
  local notify_name="${1:-${HYPR_WALLPAPER_NOTIFY_NAME:-}}"
  local notify_icon="${2:-${HYPR_WALLPAPER_NOTIFY_ICON:-}}"
  local notify_body="${3:-${wallpaper_notify_body:-}}"
  local -a notify_args=()
  local notify_title="Wallpaper: ${notify_name}"
  local elapsed_label=""

  # `notify` only re-displays the current wallpaper, so it applied nothing to time.
  if [[ -z "${notify_body}" && "${wallpaper_action}" != "notify" ]]; then
    if hypr_elapsed_label_into elapsed_label "${wallpaper_started_ms:-}"; then
      notify_body="Time: ${elapsed_label}"
    fi
  fi

  [[ -n "${notify_icon}" ]] && notify_args+=(-i "${notify_icon}")
  [[ "${wallpaper_is_global}" == "true" ]] || notify_title="Wallpaper:${notify_name} (${wallpaper_backend})"

  if [[ -n "${notify_body}" ]]; then
    wallpaper_notify_send "${NOTIFY_BRIEF_MS}" "${notify_args[@]}" "${notify_title}" "${notify_body}"
  else
    wallpaper_notify_send "${NOTIFY_BRIEF_MS}" "${notify_args[@]}" "${notify_title}"
  fi
}
