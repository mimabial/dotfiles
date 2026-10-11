#!/usr/bin/env bash

wallpaper_configure_action() {
  wallpaper_action_handler="wallpaper_action_${wallpaper_action}"
  declare -F "${wallpaper_action_handler}" >/dev/null || {
    print_log -err "wallpaper" "Unknown action: ${wallpaper_action}"
    return 1
  }
  wallpaper_action_requires_lock=0
  wallpaper_action_requires_backend=0
  wallpaper_action_sends_notification=0
  wallpaper_action_refreshes_inventory=0
  case "${wallpaper_action}" in
    next | previous | random | set | resume | display | select | start | link)
      wallpaper_action_requires_lock=1
      wallpaper_wait_for_lock=1 ;;
  esac
  case "${wallpaper_action}" in
    next | previous | random | set | resume | display | link) wallpaper_action_requires_backend=1 ;;
  esac
  case "${wallpaper_action}" in
    next | previous | random | set | resume | notify | select) wallpaper_action_sends_notification=1 ;;
  esac
  case "${wallpaper_action}" in
    next | previous | random | resume | select | start | link) wallpaper_action_refreshes_inventory=1 ;;
  esac
  return 0
}

wallpaper_acquire_lock_if_needed() {
  [[ "${wallpaper_action_requires_lock}" -eq 1 ]] || return 0

  local wallpaper_lock=""
  wallpaper_lock="$(hypr_lock_path_ensure_parent wallpaper_switch)"
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

wallpaper_refresh_inventory_if_needed() {
  [[ "${wallpaper_action_refreshes_inventory}" -ne 1 ]] || wallpaper_refresh_inventory_and_prune_async
}

wallpaper_require_backend() {
  if [[ -z "${wallpaper_backend}" ]] && [[ "${wallpaper_action_requires_backend}" -eq 1 ]]; then
    print_log -sec "wallpaper" -err "No backend specified"
    print_log -sec "wallpaper" " Please specify a backend, try '--backend awww'"
    print_log -sec "wallpaper" " See available commands: '--help | -h'"
    exit 1
  fi
}
