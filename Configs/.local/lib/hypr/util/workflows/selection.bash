workflow_write_layout_flags() {
  local layout bar_layouts
  layout="$(sed -n 's/^[[:space:]]*runtime\.config("general\.layout",[[:space:]]*"\([^"]*\)").*/\1/p' "${active_workflow_path}" | head -n1)"
  [[ "${active_workflow_name}" == windows || "${active_workflow_name}" == macos ]] && layout=""
  state_set WORKFLOW_WINDOW_LAYOUT "${layout}" staterc
  bar_layouts="$(workflow_read_bar_layouts "${active_workflow_path}")"
  case "${active_workflow_name}" in niri | windows | macos) bar_layouts="" ;; esac
  state_set WORKFLOW_QUICKSHELL_LAYOUT "${bar_layouts}" staterc
}

workflow_write_state() {
  workflow_write_config
  printf "%s %s: %s\n" "${active_workflow_icon}" "${active_workflow_name}" "${active_workflow_description}"
  send_ephemeral_notif "hypr-workflow" -t "${NOTIFY_BRIEF_MS}" -i "preferences-desktop-display" "Workflow" "${active_workflow_icon} ${active_workflow_name}\n${active_workflow_description}"
}

workflow_apply_selection() {
  local notification_rule notification_state
  workflow_load_active
  for notification_rule in windows_90 gaming_opaque powersaver_opaque; do
    [[ "${active_workflow_name}" == "${notification_rule%%_*}" ]] && notification_state=enable || notification_state=disable
    dunstctl rule "${notification_rule}" "${notification_state}" >/dev/null 2>&1 || true
  done
  if [[ "${workflow_previous_name}" == presentation && "${active_workflow_name}" != presentation ]]; then
    restore_presentation_side_effects
  fi
  workflow_write_state
  workflow_write_layout_flags
  hyprctl reload config-only -q
  workflow_apply_bar_layout
  if [[ "${active_workflow_name}" != windows ]]; then windows_restore || return 1; fi
  if [[ "${active_workflow_name}" == macos && "${workflow_previous_name}" != macos ]]; then
    state_set selected_color_source theme staterc
    "${HYPR_LIB_DIR}/theme/theme.switch.sh" --set Tundra --quiet
  fi
  if [[ "${workflow_previous_name}" != presentation && "${active_workflow_name}" == presentation ]]; then
    apply_presentation_side_effects
  fi
}
