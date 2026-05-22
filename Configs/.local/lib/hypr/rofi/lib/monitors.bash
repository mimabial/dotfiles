#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Cached hyprctl json wrappers + focused-monitor geometry.
# External deps: rofi_focused_monitor_record, rofi_scaled_divide (core/rofi.sh).

rofi_monitors_json() {
  if [[ -z "${ROFI_MONITORS_JSON_CACHE_READY:-}" ]]; then
    declare -g ROFI_MONITORS_JSON_CACHE_READY=1
    declare -g ROFI_MONITORS_JSON_CACHE
    ROFI_MONITORS_JSON_CACHE="$(hyprctl -j monitors 2>/dev/null || true)"
  fi

  printf '%s\n' "${ROFI_MONITORS_JSON_CACHE}"
}

rofi_option_json() {
  local option="${1:-}"

  [[ -n "${option}" ]] || return 1
  declare -gA ROFI_OPTION_JSON_CACHE
  if [[ ! -v ROFI_OPTION_JSON_CACHE["${option}"] ]]; then
    ROFI_OPTION_JSON_CACHE["${option}"]="$(hyprctl -j getoption "${option}" 2>/dev/null || true)"
  fi

  printf '%s\n' "${ROFI_OPTION_JSON_CACHE["${option}"]}"
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
