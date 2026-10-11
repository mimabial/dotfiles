#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
set -euo pipefail
hypr_runtime_require state

hypr_help_guard "Usage: hyprshell util/keyboard-layout [OPTION]

Without options, prints the active layout and managed keyboard settings as JSON.

Options:
  --available                 list installed XKB layouts, variants, and options
  --use INDEX                 switch physical keyboards to layout INDEX
  --add LAYOUT [VARIANT]      add and activate an XKB layout/variant
  --select LAYOUT [VARIANT]   switch to a layout/variant, adding it if needed
  --remove INDEX              remove a configured layout safely
  --shortcut OPTION|none      set or disable the XKB group shortcut" "$@"

keyboard_config_path=${HYPR_KEYBOARD_CONFIG_FILE:-${HYPR_CONFIG_HOME}/keyboard.lua}
keyboard_config_lock_fd=""
# The autoreload value to put back once the config is committed; empty while unpaused.
keyboard_autoreload_restore_value=""

source "${BASH_SOURCE[0]%/*}/keyboard/config.bash"
source "${BASH_SOURCE[0]%/*}/keyboard/devices.bash"
source "${BASH_SOURCE[0]%/*}/keyboard/report.bash"

case "${1:-}" in
  --add|--select|--remove|--shortcut)
    source "${BASH_SOURCE[0]%/*}/keyboard/validation.bash"
    source "${BASH_SOURCE[0]%/*}/keyboard/transaction.bash"
    ;;
esac

if [[ "${1:-}" == --select ]]; then
  index=$(jq -r --arg layout "${2:-}" --arg variant "${3:-}" \
    '.layouts | map(.layout == $layout and .variant == $variant) | index(true) // empty' <<<"$(keyboard_current_settings)")
  if [[ -n "${index}" ]]; then set -- --use "${index}"; else set -- --add "${2:-}" "${3:-}"; fi
fi

action=${1:-status}
case "${action}" in
  status)
    keyboard_emit_status
    ;;
  --available)
    xkbcli list --load-exotic
    ;;
  --use)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || keyboard_error '--use needs a numeric layout index.'
    index=$2
    layout_settings=$(keyboard_current_settings)
    count=$(jq '.layouts | length' <<<"${layout_settings}")
    (( index < count )) || keyboard_error 'That keyboard layout is no longer configured.'
    keyboard_switch_typing_devices "${index}" || keyboard_error 'The physical keyboards could not be switched.'
    keyboard_emit_status "${layout_settings}"
    ;;
  --add)
    layout=${2:-}; variant=${3:-}
    [[ "${layout}" =~ ^[A-Za-z0-9_+-]+$ && "${variant}" =~ ^[A-Za-z0-9_+-]*$ ]] \
      || keyboard_error '--add needs a valid XKB layout and optional variant.'
    keyboard_acquire_config_lock
    layout_settings=$(keyboard_current_settings)
    next=$(jq -c --arg layout "${layout}" --arg variant "${variant}" '
      if any(.layouts[]; .layout == $layout and .variant == $variant)
      then error("duplicate") else .layouts += [{layout: $layout, variant: $variant}] end
    ' <<<"${layout_settings}" 2>/dev/null) || keyboard_error 'That layout and variant is already configured.'
    keyboard_commit_settings "${next}" "$(jq '.layouts | length' <<<"${layout_settings}")"
    ;;
  --remove)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || keyboard_error '--remove needs a numeric layout index.'
    index=$2
    keyboard_acquire_config_lock
    layout_settings=$(keyboard_current_settings)
    count=$(jq '.layouts | length' <<<"${layout_settings}")
    (( count > 1 )) || keyboard_error 'Keep at least one keyboard layout.'
    (( index < count )) || keyboard_error 'That keyboard layout is no longer configured.'
    current=$(keyboard_active_layout_index)
    if (( index < current )); then requested=$((current - 1)); elif (( index == current )); then requested=${index}; else requested=$current; fi
    (( requested < count - 1 )) || requested=$((count - 2))
    next=$(jq -c --argjson index "${index}" '.layouts |= del(.[$index])' <<<"${layout_settings}")
    index_in_every_keymap=0
    keyboard_commit_settings "${next}" "${requested}" "${index_in_every_keymap}" "${current}"
    ;;
  --shortcut)
    shortcut=${2:-}
    [[ "${shortcut}" == none || "${shortcut}" =~ ^grp:[A-Za-z0-9_+-]+$ ]] \
      || keyboard_error '--shortcut needs an XKB grp option or none.'
    [[ "${shortcut}" == none ]] && shortcut=""
    keyboard_acquire_config_lock
    layout_settings=$(keyboard_current_settings)
    next=$(jq -c --arg shortcut "${shortcut}" '.switchOption = $shortcut' <<<"${layout_settings}")
    keyboard_commit_settings "${next}" "$(keyboard_active_layout_index)"
    ;;
  *)
    keyboard_error "Unknown option: ${action}"
    ;;
esac
