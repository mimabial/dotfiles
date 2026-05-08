#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

list_power_profiles() {
  powerprofilesctl list |
    awk '/^\s*[* ]\s*[a-zA-Z0-9\-]+:$/ { gsub(/^[*[:space:]]+|:$/, ""); print }'
}

profile_in_list() {
  local needle="$1"
  shift
  local item=""
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

pick_profile_by_preference() {
  local profiles_name="$1"
  shift
  local -n profiles_ref="${profiles_name}"
  local preferred=""

  for preferred in "$@"; do
    if profile_in_list "${preferred}" "${profiles_ref[@]}"; then
      printf '%s\n' "${preferred}"
      return 0
    fi
  done

  [[ "${#profiles_ref[@]}" -gt 0 ]] && printf '%s\n' "${profiles_ref[0]}"
}

resolve_target_profiles() {
  local out_ac_name="$1"
  local out_battery_name="$2"
  local -a profiles=()

  mapfile -t profiles < <(list_power_profiles)
  [[ "${#profiles[@]}" -gt 0 ]] || return 1

  printf -v "${out_ac_name}" '%s' "$(pick_profile_by_preference profiles performance balanced power-saver)"
  printf -v "${out_battery_name}" '%s' "$(pick_profile_by_preference profiles balanced power-saver performance)"
}

has_battery_device() {
  local battery_path=""
  for battery_path in /sys/class/power_supply/BAT*; do
    [[ -e "${battery_path}" ]] && return 0
  done
  return 1
}

ac_online_from_sysfs() {
  local supply_dir=""
  local found_mains=1
  local type_file=""
  local online_file=""
  local type_value=""
  local online_value=""

  for supply_dir in /sys/class/power_supply/*; do
    [[ -d "${supply_dir}" ]] || continue
    type_file="${supply_dir}/type"
    online_file="${supply_dir}/online"
    [[ -r "${type_file}" ]] || continue
    type_value="$(<"${type_file}")"
    [[ "${type_value}" == "Mains" ]] || continue
    found_mains=0
    [[ -r "${online_file}" ]] || continue
    online_value="$(<"${online_file}")"
    [[ "${online_value}" == "1" ]] && return 0
  done

  [[ "${found_mains}" -eq 0 ]] && return 1
  return 2
}

ac_online_from_upower() {
  local line_power_path=""
  local online_value=""

  line_power_path="$(upower -e 2>/dev/null | awk '/line_power_/ { print; exit }')"
  [[ -n "${line_power_path}" ]] || return 1

  online_value="$(upower -i "${line_power_path}" 2>/dev/null | awk '/^[[:space:]]*online:/ { print $2; exit }')"
  [[ "${online_value}" == "yes" ]]
}

is_ac_online() {
  local sysfs_status=0

  if ac_online_from_sysfs; then
    return 0
  fi
  sysfs_status=$?

  case "${sysfs_status}" in
    1)
      return 1
      ;;
  esac

  ac_online_from_upower
}

current_power_profile() {
  powerprofilesctl get 2>/dev/null || true
}

apply_power_profile() {
  local target_profile="$1"
  local current_profile=""

  [[ -n "${target_profile}" ]] || return 1
  current_profile="$(current_power_profile)"
  [[ "${current_profile}" == "${target_profile}" ]] && return 0

  powerprofilesctl set "${target_profile}"
  print_log -sec "power" -stat "profile" "${target_profile}"
}

apply_auto_profile() {
  local ac_profile=""
  local battery_profile=""
  local target_profile=""

  resolve_target_profiles ac_profile battery_profile || {
    print_log -sec "power" -warn "skip" "no power profiles available"
    return 1
  }

  if has_battery_device; then
    if is_ac_online; then
      target_profile="${ac_profile}"
    else
      target_profile="${battery_profile}"
    fi
  else
    target_profile="${ac_profile}"
  fi

  apply_power_profile "${target_profile}"
}

monitor_power_events() {
  upower --monitor-detail 2>/dev/null | while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    apply_auto_profile || true
  done
}

usage() {
  cat <<'EOF'
Usage: powerprofiles.auto.sh [--once]

Options:
  --once    Apply the current automatic power profile and exit
  -h        Show this help
EOF
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --once)
      apply_auto_profile
      exit 0
      ;;
    "")
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  command -v powerprofilesctl >/dev/null 2>&1 || {
    print_log -sec "power" -err "missing" "powerprofilesctl"
    exit 1
  }
  command -v upower >/dev/null 2>&1 || {
    print_log -sec "power" -err "missing" "upower"
    exit 1
  }

  apply_auto_profile
  monitor_power_events
}

main "$@"
