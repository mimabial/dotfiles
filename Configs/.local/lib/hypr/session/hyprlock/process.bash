hyprlock_stop_process() {
  hypr_user_pkill -x hyprlock >/dev/null 2>&1 || true
}

hyprlock_reload_process() {
  hypr_user_pkill -USR2 -x hyprlock >/dev/null 2>&1 || true
}
