#!/usr/bin/env bash

wallpaper_load_picker() {
  source "${HYPR_LIB_DIR}/wallpaper/lib/catalog-json.bash" || return 1
  source "${HYPR_LIB_DIR}/wallpaper/lib/picker.bash"
}

wallpaper_execute_action() {
  local -A backend_action_flags=([next]=n [previous]=p [random]=r [set]=s [get]=g [output]=o)
  export WALLPAPER_SET_FLAG="${backend_action_flags[${wallpaper_action}]:-${wallpaper_action}}"
  "${wallpaper_action_handler}"
}

wallpaper_action_next() { wallpaper_ensure_catalog; wallpaper_select_adjacent n; }
wallpaper_action_previous() { wallpaper_ensure_catalog; wallpaper_select_adjacent p; }
wallpaper_action_random() {
  wallpaper_ensure_catalog
  selected_wallpaper_index="$(wallpaper_random_index "${#wallpaper_paths[@]}")" || exit 1
  wallpaper_apply_selected
}
wallpaper_action_set() {
  [[ -f "${wallpaper_path}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${wallpaper_path}"; exit 1; }
  wallpaper_catalog_load_file "${wallpaper_path}" || exit 1
  wallpaper_apply_selected
}
wallpaper_action_resume() {
  wallpaper_select_current_or_first "wall.set not in current theme, using first wallpaper"
  wallpaper_apply_selected
}
wallpaper_action_display() {
  [[ -e "${active_wallpaper_link}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"; exit 1; }
  [[ "${wallpaper_is_global}" != true ]] || ln -fs "$(wallpaper_resolve_path "${active_wallpaper_link}")" "${current_wallpaper_link}"
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
  wallpaper_apply_selected
}
wallpaper_action_get() {
  [[ -e "${active_wallpaper_link}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"; exit 1; }
  realpath "${active_wallpaper_link}"
  exit 0
}
wallpaper_action_output() {
  print_log -sec "wallpaper" "Current wallpaper copied to: ${wallpaper_output}"
  cp -f "${active_wallpaper_link}" "${wallpaper_output}"
  exit "$?"
}
wallpaper_action_clean() { wallpaper_prune_orphaned_thumbnails; exit 0; }
wallpaper_action_select() { wallpaper_load_picker || exit 1; wallpaper_pick; wallpaper_catalog_load_file "${selected_wallpaper_path}" || exit 1; wallpaper_apply_selected; }
wallpaper_action_link() {
  local theme_wallpaper="${HYPR_THEME_DIR}/wall.set"
  [[ -e "${theme_wallpaper}" ]] || { print_log -err "wallpaper" "No theme wallpaper found: ${theme_wallpaper}"; exit 1; }
  wallpaper_catalog_load_file "${theme_wallpaper}" || exit 1
  wallpaper_apply_selected
  exit 0
}
wallpaper_action_json() { source "${HYPR_LIB_DIR}/wallpaper/lib/catalog-json.bash" || exit 1; wallpaper_json; exit 0; }
