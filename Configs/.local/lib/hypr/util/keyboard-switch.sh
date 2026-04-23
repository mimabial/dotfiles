#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
lib_root="$(cd -- "${script_dir}/../.." && pwd -P)"
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

usage() {
  cat <<'EOF'
Usage: hyprshell keyboard-switch.sh [--sync-current] [--quiet]

Options:
  --sync-current   Align all keyboards and keybindings.conf to the current active layout
  --quiet          Suppress the layout notification
  -h, --help       Show this help
EOF
}

layout_keybindings_variant_for_keymap() {
  local target_keymap="${1:-}"

  case "${target_keymap}" in
    *French*)
      printf 'fr\n'
      ;;
    *)
      printf 'us\n'
      ;;
  esac
}

sync_layout_keybindings() {
  local target_keymap="$1"
  local variant=""
  local source_file=""
  local target_file="${XDG_CONFIG_HOME}/hypr/keybindings.conf"

  variant="$(layout_keybindings_variant_for_keymap "${target_keymap}")"
  source_file="${XDG_CONFIG_HOME}/hypr/keybindings.${variant}.conf"

  [[ -r "${source_file}" ]] || {
    print_log -err "Missing keybindings variant: ${source_file}"
    return 1
  }

  if ! cmp -s "${source_file}" "${target_file}" 2>/dev/null; then
    cp "${source_file}" "${target_file}" || return 1
    hyprctl reload >/dev/null 2>&1 || return 1
  fi
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

current_reference_keymap() {
  local keyboards_json="$1"
  local reference_name="$2"

  keyboard_active_keymap_from_json "${keyboards_json}" "${reference_name}"
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
  local sync_current_only=0
  local notify_enabled=1
  local keyboards_json=""
  local reference_name=""
  local target_keymap=""
  local keyboard_name=""

  while (($#)); do
    case "$1" in
      --sync-current)
        sync_current_only=1
        ;;
      --quiet)
        notify_enabled=0
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        return 1
        ;;
    esac
    shift
  done

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

  if [[ "${sync_current_only}" -eq 1 ]]; then
    target_keymap="$(current_reference_keymap "${keyboards_json}" "${reference_name}")"
  else
    hyprctl switchxkblayout "${reference_name}" next >/dev/null 2>&1 || return 1
    keyboards_json="$(keyboard_devices_json)"
    target_keymap="$(keyboard_active_keymap_from_json "${keyboards_json}" "${reference_name}")"
  fi
  [[ -n "${target_keymap}" ]] || return 1

  while IFS= read -r keyboard_name; do
    [[ -n "${keyboard_name}" ]] || continue
    [[ "${keyboard_name}" == "${reference_name}" ]] && continue
    sync_keyboard_to_keymap "${keyboard_name}" "${target_keymap}" || return 1
  done < <(keyboard_name_list <<<"${keyboards_json}")

  sync_layout_keybindings "${target_keymap}" || return 1

  if [[ "${notify_enabled}" -eq 1 ]]; then
    notify_send_safe \
      -a "Keyboard switch" \
      -r 91190 \
      -t 800 \
      -i "${ICONS_DIR}/Pywal16-Icon/keyboard.svg" \
      "${target_keymap}" || true
  fi
}

main "$@"
