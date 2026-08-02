#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Cached hyprctl json wrappers + focused-monitor geometry.
# External deps: rofi_focused_monitor_record, rofi_scaled_divide (core/rofi.sh).

rofi_hypr_snapshot() {
  [[ -n "${ROFI_HYPR_SNAPSHOT_READY:-}" ]] && return 0
  local -a data=()
  mapfile -t data < <(
    hyprctl --batch -j 'monitors all;cursorpos;getoption decoration:rounding;getoption general:border_size;getoption decoration:active_opacity;getoption general:gaps_out;layers' 2>/dev/null |
      jq -cs '.[]' 2>/dev/null
  )
  declare -g ROFI_HYPR_SNAPSHOT_READY=1 ROFI_MONITORS_JSON_CACHE="${data[0]:-[]}" ROFI_CURSOR_JSON_CACHE="${data[1]:-{}}"
  declare -gA ROFI_OPTION_JSON_CACHE
  ROFI_OPTION_JSON_CACHE[decoration:rounding]="${data[2]:-{}}"
  ROFI_OPTION_JSON_CACHE[general:border_size]="${data[3]:-{}}"
  ROFI_OPTION_JSON_CACHE[decoration:active_opacity]="${data[4]:-{}}"
  ROFI_OPTION_JSON_CACHE[general:gaps_out]="${data[5]:-{}}"
  declare -g ROFI_LAYERS_JSON_CACHE="${data[6]:-{}}"
  declare -g HYPR_MONITORS_JSON_CACHE_READY=1 HYPR_MONITORS_JSON_CACHE="${ROFI_MONITORS_JSON_CACHE}"
}

rofi_monitors_json() {
  rofi_hypr_snapshot
  printf '%s\n' "${ROFI_MONITORS_JSON_CACHE}"
}

rofi_option_json() {
  local option="${1:-}"

  [[ -n "${option}" ]] || return 1
  rofi_hypr_snapshot
  if [[ ! -v ROFI_OPTION_JSON_CACHE["${option}"] ]]; then
    ROFI_OPTION_JSON_CACHE["${option}"]="$(hyprctl -j getoption "${option}" 2>/dev/null || true)"
  fi

  printf '%s\n' "${ROFI_OPTION_JSON_CACHE["${option}"]}"
}

rofi_cursor_json() {
  rofi_hypr_snapshot
  printf '%s\n' "${ROFI_CURSOR_JSON_CACHE}"
}

rofi_layers_json() {
  rofi_hypr_snapshot
  printf '%s\n' "${ROFI_LAYERS_JSON_CACHE}"
}

rofi_focused_monitor_logical_size() {
  local monitor_line=""
  local mon_width mon_height mon_scale logical_width logical_height

  monitor_line="$(rofi_focused_monitor_record 2>/dev/null || true)"
  if [[ -z "${monitor_line}" ]]; then
    printf '1920 1080\n'
    return 0
  fi

  IFS=$'\t' read -r mon_width mon_height mon_scale _ <<<"${monitor_line}"
  rofi_positive_decimal "${mon_scale}" || mon_scale=1
  logical_width="$(rofi_scaled_divide "${mon_width}" "${mon_scale}" 1 2>/dev/null || true)"
  logical_height="$(rofi_scaled_divide "${mon_height}" "${mon_scale}" 1 2>/dev/null || true)"
  [[ "${logical_width}" =~ ^[0-9]+$ ]] || logical_width=1
  [[ "${logical_height}" =~ ^[0-9]+$ ]] || logical_height=1
  printf '%s %s\n' "${logical_width}" "${logical_height}"
}
