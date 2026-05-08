#!/usr/bin/env bash

# Toggle to pop-out a tile to stay fixed on a display basis.

set -euo pipefail

CORE_COMMON="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh"

if ! declare -F hypr_focused_monitor_geometry >/dev/null 2>&1 \
  || ! declare -F hypr_window_edge_padding_px >/dev/null 2>&1; then
  [[ -r "${CORE_COMMON}" ]] || {
    printf 'Missing core helper: %s\n' "${CORE_COMMON}" >&2
    exit 1
  }
  # shellcheck source=/dev/null
  source "${CORE_COMMON}"
fi

normalize_uint() {
  local value="${1:-}"
  local default_value="${2:-0}"

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

resolve_active_window() {
  hyprctl activewindow -j
}

read_normalized_monitor_geometry() {
  local monitor_info="$1"
  local -n geometry_ref="$2"
  local -a default_values=(1 1 0 0 0 0)
  local index=0

  IFS=$'\t' read -r _ _ geometry_ref[0] geometry_ref[1] geometry_ref[2] geometry_ref[3] geometry_ref[4] geometry_ref[5] <<<"${monitor_info}"
  for index in "${!geometry_ref[@]}"; do
    geometry_ref["${index}"]="$(normalize_uint "${geometry_ref[${index}]}" "${default_values[${index}]}")"
  done
}

unpin_window() {
  local addr="$1"

  hyprctl -q --batch \
    "dispatch pin address:$addr;" \
    "dispatch togglefloating address:$addr;" \
    "dispatch tagwindow -pop address:$addr;"
}

pin_window() {
  local addr="$1"
  local monitor_info=""
  local -a monitor_geometry=()
  local monitor_width=1
  local monitor_height=1
  local reserved_left=0
  local reserved_top=0
  local reserved_right=0
  local reserved_bottom=0
  local edge_padding=12
  local usable_width=1
  local usable_height=1
  local pip_width=1
  local pip_height=1

  monitor_info="$(hypr_focused_monitor_geometry)" || return 1
  read_normalized_monitor_geometry "${monitor_info}" monitor_geometry
  monitor_width="${monitor_geometry[0]}"
  monitor_height="${monitor_geometry[1]}"
  reserved_left="${monitor_geometry[2]}"
  reserved_top="${monitor_geometry[3]}"
  reserved_right="${monitor_geometry[4]}"
  reserved_bottom="${monitor_geometry[5]}"

  edge_padding="$(hypr_window_edge_padding_px)"
  edge_padding="$(normalize_uint "${edge_padding}" 12)"

  usable_width=$((monitor_width - reserved_left - reserved_right - edge_padding * 2))
  usable_height=$((monitor_height - reserved_top - reserved_bottom - edge_padding * 2))
  ((usable_width > 0)) || usable_width=1
  ((usable_height > 0)) || usable_height=1

  pip_width=$(awk "BEGIN {printf \"%.0f\", $usable_width * 0.7}")
  pip_height=$(awk "BEGIN {printf \"%.0f\", $usable_height * 0.7}")

  hyprctl -q --batch \
    "dispatch togglefloating address:$addr;" \
    "dispatch resizewindowpixel exact ${pip_width} ${pip_height},address:$addr;" \
    "dispatch centerwindow 1,address:$addr;" \
    "dispatch pin address:$addr;" \
    "dispatch alterzorder top address:$addr;" \
    "dispatch tagwindow +pop address:$addr;"
}

main() {
  local active=""
  local pinned=""
  local addr=""

  active="$(resolve_active_window)"
  pinned="$(jq '.pinned' <<<"${active}")"
  addr="$(jq -r '.address' <<<"${active}")"

  [ -z "${addr}" ] && {
    echo "No active window"
    return 0
  }

  if [ "${pinned}" = "true" ]; then
    unpin_window "${addr}"
  else
    pin_window "${addr}"
  fi
}

main "$@"
