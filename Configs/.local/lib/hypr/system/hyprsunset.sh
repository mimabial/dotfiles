#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1

source "${BASH_SOURCE[0]%/*}/nightlight/settings.bash"
source "${BASH_SOURCE[0]%/*}/nightlight/arguments.bash"
source "${BASH_SOURCE[0]%/*}/nightlight/actions.bash"
source "${BASH_SOURCE[0]%/*}/nightlight/runtime.bash"
source "${BASH_SOURCE[0]%/*}/nightlight/render.bash"

main() {
  local -A options=(
    [notify]="${HYPRSUNSET_NOTIFY:-true}"
    [action]=""
    [color_mode]="temp"
    [custom_step]=""
    [signal_proc]=""
    [temperature_step_kelvin]="${DEFAULT_TEMPERATURE_STEP_KELVIN}"
    [gamma_step_percent]="${DEFAULT_GAMMA_STEP_PERCENT}"
    [help]=false
  )
  local -A state=(
    [temperature_kelvin]=""
    [gamma_percent]=""
    [enabled]=""
    [new_temperature_kelvin]=""
    [new_gamma_percent]=""
  )

  if [ "$#" -le 0 ]; then
    echo "No arguments provided" >&2
    nightlight_show_help >&2
    return 1
  fi
  nightlight_parse_args options "$@" || return $?
  if [ "${options[help]}" = true ]; then
    nightlight_show_help
    return 0
  fi

  nightlight_load_state state
  nightlight_prepare_action_values options state || return 1
  nightlight_apply_action_to_state options state
  [ "${options[notify]}" = true ] && nightlight_send_notification options state
  nightlight_send_signal_to_process "${options[signal_proc]}"
  nightlight_sync_runtime_state options state
  nightlight_generate_status state
}

main "$@"
