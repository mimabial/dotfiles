#!/usr/bin/env bash

wallpaper_load_picker() {
  source "${HYPR_LIB_DIR}/wallpaper/lib/catalog-json.bash" || return 1
  source "${HYPR_LIB_DIR}/wallpaper/lib/picker.bash"
}

wallpaper_execute_action() {
  local -A backend_action_flags=([next]=n [previous]=p [random]=r [set]=s [get]=g [output]=o)
  export WALLPAPER_SET_FLAG="${backend_action_flags[${wallpaper_action}]:-${wallpaper_action}}"
  "wallpaper_action_${wallpaper_action}"
}

wallpaper_action_next() { wallpaper_ensure_catalog && wallpaper_apply_adjacent n; }
wallpaper_action_previous() { wallpaper_ensure_catalog && wallpaper_apply_adjacent p; }
wallpaper_action_random() {
  local index=""
  wallpaper_ensure_catalog || return 1
  index="$(wallpaper_random_index "${#wallpaper_paths[@]}")" || exit 1
  wallpaper_apply_selected "${wallpaper_paths[index]}"
}
wallpaper_action_set() {
  [[ -f "${wallpaper_path}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${wallpaper_path}"; exit 1; }
  wallpaper_apply_file "${wallpaper_path}"
}
wallpaper_action_resume() {
  local chosen_wallpaper=""
  wallpaper_current_or_first_into chosen_wallpaper "wall.set not in current theme, using first wallpaper" || return 1
  wallpaper_apply_selected "${chosen_wallpaper}"
}
wallpaper_action_display() {
  [[ -e "${active_wallpaper_link}" ]] || { print_log -err "wallpaper" "Wallpaper not found: ${active_wallpaper_link}"; exit 1; }
  [[ "${wallpaper_is_global}" != true ]] || ln -fs "$(wallpaper_resolve_path "${active_wallpaper_link}")" "${current_wallpaper_link}"
}
wallpaper_action_notify() {
  local chosen_wallpaper=""
  wallpaper_current_or_first_into chosen_wallpaper "wall.set not in current theme, using first wallpaper for notification" || exit 1
  wallpaper_prepare_notification_payload "${chosen_wallpaper}"
  wallpaper_notify_result
  exit 0
}
wallpaper_action_start() {
  local current_wallpaper=""
  [[ -e "${active_wallpaper_link}" ]] || { print_log -err "wallpaper" "No current wallpaper found: ${active_wallpaper_link}"; exit 1; }
  export WALLPAPER_RELOAD_ALL=0
  current_wallpaper="$(realpath "${active_wallpaper_link}")"
  wallpaper_apply_file "${current_wallpaper}"
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
wallpaper_action_select() {
  local picked_wallpaper=""
  wallpaper_load_picker || exit 1
  wallpaper_pick_into picked_wallpaper || exit 1
  [[ -n "${picked_wallpaper}" ]] || exit 0
  wallpaper_apply_file "${picked_wallpaper}"
}
wallpaper_action_link() {
  local theme_wallpaper="${HYPR_THEME_DIR}/wall.set"
  [[ -e "${theme_wallpaper}" ]] || { print_log -err "wallpaper" "No theme wallpaper found: ${theme_wallpaper}"; exit 1; }
  wallpaper_apply_file "${theme_wallpaper}" || exit 1
  exit 0
}
wallpaper_action_json() { source "${HYPR_LIB_DIR}/wallpaper/lib/catalog-json.bash" || exit 1; wallpaper_json; exit 0; }
