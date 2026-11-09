#!/usr/bin/env bash

wallpaper_policy_takes_lock() {
  case "$1" in next | previous | random | set | resume | display | select | start | link) return 0 ;; esac
  return 1
}

wallpaper_policy_needs_backend() {
  case "$1" in next | previous | random | set | resume | display | link) return 0 ;; esac
  return 1
}

wallpaper_policy_notifies() {
  case "$1" in next | previous | random | set | resume | notify | select) return 0 ;; esac
  return 1
}

wallpaper_policy_refreshes_inventory() {
  case "$1" in next | previous | random | resume | select | start | link) return 0 ;; esac
  return 1
}

wallpaper_configure_action() {
  declare -F "wallpaper_action_${wallpaper_action}" >/dev/null || {
    print_log -err "wallpaper" "Unknown action: ${wallpaper_action}"
    return 1
  }
  if wallpaper_policy_takes_lock "${wallpaper_action}"; then
    wallpaper_wait_for_lock=1
  fi
}

wallpaper_acquire_lock_if_needed() {
  wallpaper_policy_takes_lock "${wallpaper_action}" || return 0

  local wallpaper_lock=""
  hypr_lock_path_into wallpaper_lock wallpaper_switch
  exec {wallpaper_lock_fd}>"${wallpaper_lock}"

  if ! flock -n "${wallpaper_lock_fd}"; then
    if [[ "${wallpaper_wait_for_lock}" -eq 1 ]]; then
      print_log -sec "wallpaper" -stat "wait" "Another wallpaper operation is already in progress"
      flock "${wallpaper_lock_fd}"
    else
      print_log -sec "wallpaper" -stat "drop" "Another wallpaper operation is already in progress"
      return 1
    fi
  fi
}

wallpaper_refresh_inventory_if_needed() {
  ! wallpaper_policy_refreshes_inventory "${wallpaper_action}" || wallpaper_refresh_inventory_and_prune_async
}

wallpaper_require_backend() {
  if [[ -z "${wallpaper_backend}" ]] && wallpaper_policy_needs_backend "${wallpaper_action}"; then
    print_log -sec "wallpaper" -err "No backend specified"
    print_log -sec "wallpaper" " Please specify a backend, try '--backend awww'"
    print_log -sec "wallpaper" " See available commands: '--help | -h'"
    return 1
  fi
}
