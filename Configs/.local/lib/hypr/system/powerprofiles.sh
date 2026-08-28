#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1

usage="Usage: hyprshell system/powerprofiles.sh [--set PROFILE|--cycle|--restore]
List or change power profiles. AC and battery choices are remembered separately.
Manual changes are locked while GameMode is active."
hypr_help_guard "${usage}" "$@"

list_profiles() {
  busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles Profiles |
    grep -oP '"Profile" s "\K[^"]+'
}

gamemode_active() {
  [[ "$(busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount 2>/dev/null)" =~ ^i[[:space:]]+[1-9][0-9]*$ ]]
}

active_profile() {
  local type profile
  read -r type profile < <(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile)
  printf '%s\n' "${profile//\"/}"
}

profile_available() {
  local wanted="$1"
  local profile=""

  while IFS= read -r profile; do
    [[ "${profile}" == "${wanted}" ]] && return 0
  done < <(list_profiles)
  return 1
}

power_source() {
  if [[ "$(busctl --system get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null)" == "b true" ]]; then
    printf 'battery\n'
  else
    printf 'ac\n'
  fi
}

profile_state_file() {
  printf '%s/powerprofiles/%s\n' "${HYPR_STATE_HOME}" "$1"
}

remember_profile() {
  local source="$1"
  local profile="$2"
  local state_file=""
  local tmp_file=""

  state_file="$(profile_state_file "${source}")"
  mkdir -p "$(dirname "${state_file}")"
  tmp_file="$(mktemp "${state_file}.tmp.XXXXXX")"
  printf '%s\n' "${profile}" >"${tmp_file}"
  mv -f -- "${tmp_file}" "${state_file}"
}

set_profile() {
  local profile="$1"
  local notify_lock="${2:-1}"

  if gamemode_active; then
    if [[ "${notify_lock}" == 1 ]]; then
      notify_send_safe -a hyprshell "Power profile locked" "GameMode is driving the CPU governor until the game exits." || true
    fi
    return 1
  fi
  profile_available "${profile}" || {
    printf 'Power profile is not available: %s\n' "${profile}" >&2
    return 1
  }
  busctl --system set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile s "${profile}"
}

set_and_remember_profile() {
  local profile="$1"
  set_profile "${profile}" || return
  remember_profile "$(power_source)" "${profile}"
}

restore_profile() {
  local source=""
  local state_file=""
  local profile=""

  gamemode_active && return 0
  source="$(power_source)"
  state_file="$(profile_state_file "${source}")"
  [[ -r "${state_file}" ]] && read -r profile <"${state_file}"

  if [[ -z "${profile}" ]] || ! profile_available "${profile}"; then
    if [[ "${source}" == "ac" ]] && profile_available performance; then
      profile="performance"
    else
      profile="balanced"
    fi
  fi

  [[ "$(active_profile)" == "${profile}" ]] || set_profile "${profile}" 0
}

case "${1:-}" in
  "") list_profiles ;;
  --set) [[ -n "${2:-}" ]] || { printf '%s\n' "${usage}" >&2; exit 2; }; set_and_remember_profile "$2" ;;
  --cycle)
    mapfile -t profiles < <(list_profiles)
    ((${#profiles[@]})) || exit 0
    current="$(active_profile)"
    for i in "${!profiles[@]}"; do
      [[ "${profiles[i]}" == "${current}" ]] || continue
      set_and_remember_profile "${profiles[(i + 1) % ${#profiles[@]}]}"
      exit
    done
    set_and_remember_profile "${profiles[0]}"
    ;;
  --restore) restore_profile ;;
  *) printf '%s\n' "${usage}" >&2; exit 2 ;;
esac
