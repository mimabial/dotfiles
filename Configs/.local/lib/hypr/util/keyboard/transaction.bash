keyboard_disable_autoreload_value() {
  hyprctl -j getoption misc:disable_autoreload 2>/dev/null \
    | jq -er '.bool | if . then "true" else "false" end'
}

keyboard_set_disable_autoreload() {
  hypr_lua_apply "hl.config({ misc = { disable_autoreload = $1 } })" >/dev/null 2>&1
}

keyboard_pause_autoreload() {
  local was_disabled=""
  was_disabled=$(keyboard_disable_autoreload_value) \
    || keyboard_error 'Hyprland autoreload state could not be read; nothing was changed.'
  keyboard_set_disable_autoreload true \
    || keyboard_error 'Hyprland autoreload could not be paused safely; nothing was changed.'
  keyboard_autoreload_restore_value="${was_disabled}"
}

keyboard_resume_autoreload() {
  [[ -n "${keyboard_autoreload_restore_value}" ]] || return 0
  keyboard_set_disable_autoreload "${keyboard_autoreload_restore_value}" || true
  keyboard_autoreload_restore_value=""
}

keyboard_apply_live_config() {
  local layout_settings="$1" layouts="" variants="" options=""
  layouts=$(hypr_lua_quote "$(keyboard_layout_csv "${layout_settings}")")
  variants=$(hypr_lua_quote "$(keyboard_variant_csv "${layout_settings}")")
  options=$(hypr_lua_quote "$(keyboard_options_csv "${layout_settings}")")
  hypr_lua_apply "hl.config({ input = { kb_layout = ${layouts}, kb_variant = ${variants}, kb_options = ${options} } })" >/dev/null 2>&1
}

keyboard_live_settings_match() {
  [[ "$(keyboard_option_string input:kb_layout)" == "$(keyboard_layout_csv "$1")" ]] \
    && [[ "$(keyboard_option_string input:kb_variant)" == "$(keyboard_variant_csv "$1")" ]] \
    && [[ "$(keyboard_option_string input:kb_options)" == "$(keyboard_options_csv "$1")" ]]
}

keyboard_restore_config() {
  local backup="$1" had_config="$2"
  if [[ "${had_config}" == true ]]; then
    cp -p -- "${backup}" "${keyboard_config_path}"
  else
    rm -f -- "${keyboard_config_path}"
  fi
}

keyboard_commit_settings() {
  local layout_settings="$1" requested_index="${2:-0}" pre_apply_index="${3:-}" rollback_index="${4:-0}"
  local config_dir="" temp_config="" old_config="" previous_layout_settings="" had_config=false

  keyboard_validate_candidate "${layout_settings}"
  config_dir="${keyboard_config_path%/*}"
  mkdir -p -- "${config_dir}"
  temp_config=$(mktemp --tmpdir="${config_dir}" .keyboard.lua.XXXXXX)
  old_config=$(mktemp --tmpdir="${config_dir}" .keyboard-old.lua.XXXXXX)
  keyboard_render_config "${layout_settings}" "${temp_config}"

  if [[ -f "${keyboard_config_path}" ]] && cmp -s -- "${temp_config}" "${keyboard_config_path}"; then
    rm -f -- "${temp_config}" "${old_config}"
    keyboard_emit_status "${layout_settings}"
    return 0
  fi

  previous_layout_settings=$(keyboard_current_settings)
  if [[ -f "${keyboard_config_path}" ]]; then
    cp -p -- "${keyboard_config_path}" "${old_config}"
    had_config=true
  fi

  trap 'keyboard_resume_autoreload; rm -f -- "${temp_config}" "${old_config}"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  keyboard_pause_autoreload

  if [[ -n "${pre_apply_index}" ]] && ! keyboard_switch_all_devices "${pre_apply_index}"; then
    keyboard_switch_all_devices "${rollback_index}" \
      || keyboard_error "The keyboards could not be moved to a safe layout, and some may remain on layout index ${pre_apply_index}."
    keyboard_error 'The keyboards could not be moved to a safe layout; nothing was changed.'
  fi

  mv -f -- "${temp_config}" "${keyboard_config_path}"
  if ! keyboard_apply_live_config "${layout_settings}" || ! keyboard_live_settings_match "${layout_settings}"; then
    keyboard_restore_config "${old_config}" "${had_config}"
    keyboard_apply_live_config "${previous_layout_settings}" || true
    [[ -z "${pre_apply_index}" ]] || keyboard_restore_typing_devices "${rollback_index}"
    keyboard_error 'Hyprland rejected the keyboard configuration; the previous settings were restored.'
  fi

  keyboard_restore_typing_devices "${requested_index}"
  keyboard_resume_autoreload
  trap - EXIT HUP INT TERM
  rm -f -- "${temp_config}" "${old_config}"
  keyboard_emit_status "${layout_settings}"
}

keyboard_acquire_config_lock() {
  state_acquire_lock "${keyboard_config_path}" keyboard_config_lock_fd \
    || keyboard_error 'Keyboard settings are busy; try again in a moment.'
}
