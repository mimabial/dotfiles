#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

hypr_help_guard "Usage: hyprshell system/monitor-scale [--reverse|--select|SCALE]
Set or cycle the focused monitor's scale. Use --select for a rofi picker." "$@"

scales=(1 1.25 1.5 1.67 2 3 4)
mode="next"
target_scale=""

case "${1:-}" in
  "") ;;
  --reverse | reverse)
    mode="previous"
    ;;
  --select | select)
    mode="select"
    ;;
  *)
    if [[ "${1}" =~ ^[0-9]+([.][0-9]+)?x?$ ]]; then
      mode="set"
      target_scale="${1%x}"
    else
      printf 'Unknown monitor scale option: %s\n' "${1}" >&2
      exit 2
    fi
    ;;
esac

monitor_info="$(hyprctl monitors -j | jq -r '([.[] | select(.focused == true)][0] // .[0])')"
active_monitor="$(jq -r '.name // empty' <<<"${monitor_info}")"
current_scale="$(jq -r '.scale // 1' <<<"${monitor_info}")"
width="$(jq -r '.width // empty' <<<"${monitor_info}")"
height="$(jq -r '.height // empty' <<<"${monitor_info}")"
refresh_rate="$(jq -r '.refreshRate // empty' <<<"${monitor_info}")"
pos_x="$(jq -r '.x // 0' <<<"${monitor_info}")"
pos_y="$(jq -r '.y // 0' <<<"${monitor_info}")"
transform="$(jq -r '.transform // 0' <<<"${monitor_info}")"

if [[ -z "${active_monitor}" || -z "${width}" || -z "${height}" || -z "${refresh_rate}" ]]; then
  monitor_notify "Monitor scaling failed" "No focused monitor found"
  exit 1
fi

scale_is_preset() {
  local scale="$1"
  local preset=""

  for preset in "${scales[@]}"; do
    [[ "${scale}" == "${preset}" ]] && return 0
  done

  return 1
}

current_idx="$(
  awk -v s="${current_scale}" -v list="${scales[*]}" 'BEGIN {
    n = split(list, arr, " ")
    best = 0
    best_diff = 1000000
    for (i = 1; i <= n; i++) {
      d = s - arr[i]
      if (d < 0) d = -d
      if (d < best_diff) {
        best_diff = d
        best = i - 1
      }
    }
    print best
  }'
)"

select_scale() {
  local selected=""
  local -a rofi_args=()

  if ! command -v rofi >/dev/null 2>&1; then
    monitor_notify "Monitor scaling failed" "rofi not found"
    return 1
  fi

  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"

  rofi_build_standard_menu_args \
    rofi_args \
    "Display Scale" \
    " ${active_monitor} scale" \
    "${ROFI_MONITOR_SCALE_STYLE:-clipboard}" \
    "${ROFI_MONITOR_SCALE_SCALE:-}" \
    "${ROFI_MONITOR_SCALE_FONT:-${ROFI_FONT:-}}" \
    "listview" \
    "same"
  rofi_args+=(
    -no-show-icons
    -selected-row "${current_idx}"
    -theme-str "window { width: ${ROFI_MONITOR_SCALE_WIDTH:-22em}; height: ${ROFI_MONITOR_SCALE_HEIGHT:-24em}; } listview { lines: ${ROFI_MONITOR_SCALE_LINES:-7}; }"
  )

  selected="$(
    printf '%sx\n' "${scales[@]}" | rofi "${rofi_args[@]}"
  )" || return 0
  [[ -n "${selected}" ]] || return 0
  selected="${selected%x}"

  if ! scale_is_preset "${selected}"; then
    monitor_notify "Monitor scaling failed" "Invalid scale: ${selected}"
    return 1
  fi

  printf '%s\n' "${selected}"
}

case "${mode}" in
  next)
    target_scale="${scales[$(((current_idx + 1) % ${#scales[@]}))]}"
    ;;
  previous)
    target_scale="${scales[$(((current_idx - 1 + ${#scales[@]}) % ${#scales[@]}))]}"
    ;;
  select)
    target_scale="$(select_scale)"
    [[ -n "${target_scale}" ]] || exit 0
    ;;
  set)
    if ! scale_is_preset "${target_scale}"; then
      monitor_notify "Monitor scaling failed" "Unsupported scale: ${target_scale}"
      exit 1
    fi
    ;;
esac

new_scale="${target_scale}"
new_gdk_scale="$(monitor_gdk_scale_for "${new_scale}")"
mode="${width}x${height}@${refresh_rate}"
position="${pos_x}x${pos_y}"
fragment_name="20-scale-$(monitor_sanitize_name "${active_monitor}")"
monitor_set_fragment "${fragment_name}" "$(printf 'hl.env(\"GDK_SCALE\", %s)\nhl.monitor({output = %s, mode = %s, position = %s, scale = %s, transform = %s})' \
  "$(monitor_lua_quote "${new_gdk_scale}")" \
  "$(monitor_lua_quote "${active_monitor}")" \
  "$(monitor_lua_quote "${mode}")" \
  "$(monitor_lua_quote "${position}")" \
  "${new_scale}" \
  "${transform}")"
monitor_reload
monitor_notify "Display scaling set to ${new_scale}x" "${active_monitor} (GDK ${new_gdk_scale})"
