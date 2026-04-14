#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
lib_root="$(realpath "${script_dir}/../..")"
xdg_lib="${lib_root}/hypr/core/xdg.sh"
notify_lib="${lib_root}/hypr/core/notify.sh"
state_lib="${lib_root}/hypr/core/state.sh"

[[ -r "${xdg_lib}" ]] || {
  printf 'missing xdg bootstrap: %s\n' "${xdg_lib}" >&2
  exit 1
}
[[ -r "${notify_lib}" ]] || {
  printf 'missing notify helpers: %s\n' "${notify_lib}" >&2
  exit 1
}
[[ -r "${state_lib}" ]] || {
  printf 'missing state helpers: %s\n' "${state_lib}" >&2
  exit 1
}

# shellcheck source=/dev/null
source "${xdg_lib}" || exit 1
hypr_init_xdg_env
export ICONS_DIR="${ICONS_DIR:-${XDG_DATA_HOME}/icons}"

# shellcheck source=/dev/null
source "${notify_lib}" || exit 1
# shellcheck source=/dev/null
source "${state_lib}" || exit 1

require_commands() {
  local cmd_name=""

  for cmd_name in "$@"; do
    command -v "${cmd_name}" >/dev/null 2>&1 || {
      print_log -err "${cmd_name} is required for keyboard layout switching"
      return 1
    }
  done
}

ensure_hypr_instance_signature() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && return 0
  refresh_hypr_instance_signature
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
}

keyboard_devices_json() {
  hyprctl -j devices | jq -c '
    .keyboards
    | map(
        select(.name | test("^(power-button(-[0-9]+)?|video-bus(-[0-9]+)?|.*system-control|.*consumer-control|asus-wmi-hotkeys)$") | not)
      )
  '
}

keyboard_name_list() {
  jq -r '.[].name'
}

keyboard_active_keymap_from_json() {
  local keyboards_json="$1"
  local keyboard_name="$2"

  jq -r --arg name "${keyboard_name}" '.[] | select(.name == $name) | .active_keymap // empty' <<<"${keyboards_json}" \
    | head -n1
}

reference_keyboard_name() {
  local keyboards_json="$1"
  local name=""

  name="$(jq -r 'map(select(.main == true))[0].name // empty' <<<"${keyboards_json}")"
  [[ -n "${name}" ]] || name="$(jq -r '.[0].name // empty' <<<"${keyboards_json}")"
  [[ -n "${name}" ]] || return 1
  printf '%s\n' "${name}"
}

sync_keyboard_to_keymap() {
  local keyboard_name="$1"
  local target_keymap="$2"
  local attempts=8
  local current_keymap=""
  local keyboards_json=""

  while ((attempts > 0)); do
    keyboards_json="$(keyboard_devices_json)"
    current_keymap="$(keyboard_active_keymap_from_json "${keyboards_json}" "${keyboard_name}")"
    [[ -n "${current_keymap}" ]] || return 1
    [[ "${current_keymap}" == "${target_keymap}" ]] && return 0

    hyprctl switchxkblayout "${keyboard_name}" next >/dev/null 2>&1 || return 1
    attempts=$((attempts - 1))
  done

  keyboards_json="$(keyboard_devices_json)"
  current_keymap="$(keyboard_active_keymap_from_json "${keyboards_json}" "${keyboard_name}")"
  [[ "${current_keymap}" == "${target_keymap}" ]]
}

main() {
  local keyboards_json=""
  local reference_name=""
  local target_keymap=""
  local keyboard_name=""

  require_commands hyprctl jq
  ensure_hypr_instance_signature || {
    print_log -err "HYPRLAND_INSTANCE_SIGNATURE is not set"
    return 1
  }

  keyboards_json="$(keyboard_devices_json)"
  [[ "$(jq 'length' <<<"${keyboards_json}")" -gt 0 ]] || {
    print_log -err "No keyboard devices available for layout switching"
    return 1
  }

  reference_name="$(reference_keyboard_name "${keyboards_json}")" || return 1

  hyprctl switchxkblayout "${reference_name}" next >/dev/null 2>&1 || return 1
  keyboards_json="$(keyboard_devices_json)"
  target_keymap="$(keyboard_active_keymap_from_json "${keyboards_json}" "${reference_name}")"
  [[ -n "${target_keymap}" ]] || return 1

  while IFS= read -r keyboard_name; do
    [[ -n "${keyboard_name}" ]] || continue
    [[ "${keyboard_name}" == "${reference_name}" ]] && continue
    sync_keyboard_to_keymap "${keyboard_name}" "${target_keymap}" || return 1
  done < <(keyboard_name_list <<<"${keyboards_json}")

  notify_send_safe \
    -a "Keyboard switch" \
    -r 91190 \
    -t 800 \
    -i "${ICONS_DIR}/Pywal16-Icon/keyboard.svg" \
    "${target_keymap}" || true
}

main "$@"
