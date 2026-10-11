power_profiles_list() {
  dbus-send --system --print-reply=literal --dest=org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties.Get string:org.freedesktop.UPower.PowerProfiles string:Profiles |
    grep -oP '^\s*Profile\s+variant\s+\K\S+'
}

power_profiles_available() {
  local wanted="$1"
  local profile=""

  while IFS= read -r profile; do
    [[ "${profile}" == "${wanted}" ]] && return 0
  done < <(power_profiles_list)
  return 1
}

power_profiles_source() {
  if hypr_on_battery; then
    printf 'battery\n'
  else
    printf 'ac\n'
  fi
}

power_profiles_state_path() {
  printf '%s/powerprofiles/%s\n' "${HYPR_STATE_HOME}" "$1"
}

power_profiles_remember() {
  local source="$1"
  local profile="$2"
  local state_file=""
  local tmp_file=""

  state_file="$(power_profiles_state_path "${source}")"
  mkdir -p "${state_file%/*}"
  tmp_file="$(mktemp "${state_file}.tmp.XXXXXX")"
  printf '%s\n' "${profile}" >"${tmp_file}"
  mv -f -- "${tmp_file}" "${state_file}"
}

power_profiles_set() {
  local profile="$1"
  local notify_lock="${2:-1}"

  if hypr_gamemode_active; then
    if [[ "${notify_lock}" == 1 ]]; then
      notify_send_safe -a hyprshell "Power profile locked" "GameMode is driving the CPU governor until the game exits." || true
    fi
    return 1
  fi
  power_profiles_available "${profile}" || {
    printf 'Power profile is not available: %s\n' "${profile}" >&2
    return 1
  }
  hypr_set_power_profile "${profile}"
}

power_profiles_set_and_remember() {
  local profile="$1"
  power_profiles_set "${profile}" || return
  power_profiles_remember "$(power_profiles_source)" "${profile}"
}

power_profiles_restore() {
  local source=""
  local state_file=""
  local profile=""

  hypr_gamemode_active && return 0
  if power_manager_enabled; then
    "${HYPR_LIB_DIR}/system/power-manager.sh" apply-profile
    return
  fi
  source="$(power_profiles_source)"
  state_file="$(power_profiles_state_path "${source}")"
  [[ -r "${state_file}" ]] && read -r profile <"${state_file}"

  if [[ -z "${profile}" ]] || ! power_profiles_available "${profile}"; then
    if [[ "${source}" == "ac" ]] && power_profiles_available performance; then
      profile="performance"
    else
      profile="balanced"
    fi
  fi

  [[ "$(hypr_power_profile)" == "${profile}" ]] || power_profiles_set "${profile}" 0
}
