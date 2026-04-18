#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/window.common.bash"

usage() {
  cat <<'EOF'
Usage: hyprshell launch/summon.sh [options] <window-pattern> -- <command> [args...]

Options:
  --empty-workspace-if-occupied  Use the nearest empty workspace when the current
                                 workspace already contains another tiled window
  --width SPEC                   Target width in px or percent
  --height SPEC                  Target height in px or percent
  --align left|right|center      Horizontal placement after summon/resize
EOF
}

summon_window_to_workspace() {
  local window_address="$1"
  local workspace_name="$2"

  hyprctl -q --batch \
    "dispatch movetoworkspacesilent ${workspace_name},address:${window_address}; \
dispatch focuswindow address:${window_address}" \
    >/dev/null 2>&1
}

launch_geometry_requested() {
  [[ -n "${1:-}" || -n "${2:-}" || -n "${3:-}" ]]
}

launch_read_window_geometry_state() {
  local window_address="$1"
  local out_width_name="$2"
  local out_height_name="$3"
  local out_floating_name="$4"
  local out_workspace_name="$5"
  local window_info=""

  window_info="$(launch_wait_for_window_info_stable "${window_address}")"
  [[ -n "${window_info}" ]] || return 1

  # shellcheck disable=SC2178
  local -n out_width_ref="${out_width_name}"
  # shellcheck disable=SC2178
  local -n out_height_ref="${out_height_name}"
  # shellcheck disable=SC2178
  local -n out_floating_ref="${out_floating_name}"
  # shellcheck disable=SC2178
  local -n out_workspace_ref="${out_workspace_name}"

  IFS=$'\t' read -r out_width_ref out_height_ref out_floating_ref out_workspace_ref <<<"${window_info}"
}

launch_monitor_usable_geometry() {
  local out_padded_width_name="$1"
  local out_padded_height_name="$2"
  local out_usable_x_name="$3"
  local out_usable_y_name="$4"
  local out_usable_width_name="$5"
  local out_usable_height_name="$6"
  local monitor_x=""
  local monitor_y=""
  local monitor_width=""
  local monitor_height=""
  local reserve_left=""
  local reserve_top=""
  local reserve_right=""
  local reserve_bottom=""
  local visible_width=""
  local visible_height=""
  local edge_padding=""

  IFS=$'\t' read -r monitor_x monitor_y monitor_width monitor_height reserve_left reserve_top reserve_right reserve_bottom \
    <<<"$(launch_focused_monitor_geometry)"

  visible_width=$((monitor_width - reserve_left - reserve_right))
  visible_height=$((monitor_height - reserve_top - reserve_bottom))
  ((visible_width > 0 && visible_height > 0)) || return 1

  edge_padding="$(launch_window_edge_padding_px)"

  # shellcheck disable=SC2178
  local -n out_padded_width_ref="${out_padded_width_name}"
  # shellcheck disable=SC2178
  local -n out_padded_height_ref="${out_padded_height_name}"
  # shellcheck disable=SC2178
  local -n out_usable_x_ref="${out_usable_x_name}"
  # shellcheck disable=SC2178
  local -n out_usable_y_ref="${out_usable_y_name}"
  # shellcheck disable=SC2178
  local -n out_usable_width_ref="${out_usable_width_name}"
  # shellcheck disable=SC2178
  local -n out_usable_height_ref="${out_usable_height_name}"

  out_padded_width_ref=$((visible_width - (edge_padding * 2)))
  out_padded_height_ref=$((visible_height - (edge_padding * 2)))
  ((out_padded_width_ref > 0)) || out_padded_width_ref=1
  ((out_padded_height_ref > 0)) || out_padded_height_ref=1

  out_usable_x_ref=$((monitor_x + reserve_left + edge_padding))
  out_usable_y_ref=$((monitor_y + reserve_top + edge_padding))
  out_usable_width_ref=$((monitor_width - reserve_left - reserve_right - (edge_padding * 2)))
  out_usable_height_ref=$((monitor_height - reserve_top - reserve_bottom - (edge_padding * 2)))
  ((out_usable_width_ref > 0)) || out_usable_width_ref=1
  ((out_usable_height_ref > 0)) || out_usable_height_ref=1
}

launch_target_window_size() {
  local current_width="$1"
  local current_height="$2"
  local width_spec="$3"
  local height_spec="$4"
  local padded_width="$5"
  local padded_height="$6"
  local out_width_name="$7"
  local out_height_name="$8"

  # shellcheck disable=SC2178
  local -n out_width_ref="${out_width_name}"
  # shellcheck disable=SC2178
  local -n out_height_ref="${out_height_name}"

  out_width_ref="${current_width}"
  out_height_ref="${current_height}"
  [[ -n "${width_spec}" ]] && out_width_ref="$(launch_resolve_dimension "${width_spec}" "${padded_width}")"
  [[ -n "${height_spec}" ]] && out_height_ref="$(launch_resolve_dimension "${height_spec}" "${padded_height}")"
}

launch_ensure_window_floating() {
  local window_address="$1"
  local is_floating="$2"

  [[ "${is_floating}" == "true" ]] && return 0
  hyprctl dispatch togglefloating "address:${window_address}" >/dev/null 2>&1
}

launch_resize_window_exact() {
  local window_address="$1"
  local target_width="$2"
  local target_height="$3"

  hyprctl -q --batch \
    "dispatch resizewindowpixel exact ${target_width} ${target_height},address:${window_address}" \
    >/dev/null 2>&1
}

launch_clamp_window_size_to_usable_area() {
  local current_width="$1"
  local current_height="$2"
  local usable_width="$3"
  local usable_height="$4"
  local out_width_name="$5"
  local out_height_name="$6"

  # shellcheck disable=SC2178
  local -n out_width_ref="${out_width_name}"
  # shellcheck disable=SC2178
  local -n out_height_ref="${out_height_name}"

  out_width_ref="${current_width}"
  out_height_ref="${current_height}"
  ((current_width > usable_width)) && out_width_ref="${usable_width}"
  ((current_height > usable_height)) && out_height_ref="${usable_height}"
}

launch_compute_target_position() {
  local align="${1:-center}"
  local usable_x="$2"
  local usable_y="$3"
  local usable_width="$4"
  local usable_height="$5"
  local current_width="$6"
  local current_height="$7"
  local out_x_name="$8"
  local out_y_name="$9"
  local max_x=""
  local max_y=""
  local target_x=""
  local target_y=""

  max_x=$((usable_x + usable_width - current_width))
  max_y=$((usable_y + usable_height - current_height))
  ((max_x >= usable_x)) || max_x="${usable_x}"
  ((max_y >= usable_y)) || max_y="${usable_y}"

  case "${align}" in
    left)
      target_x="${usable_x}"
      ;;
    right)
      target_x="${max_x}"
      ;;
    center)
      target_x=$((usable_x + (usable_width - current_width) / 2))
      ;;
    *)
      echo "Unknown align value: ${align}" >&2
      return 1
      ;;
  esac

  target_y=$((usable_y + (usable_height - current_height) / 2))
  ((target_x < usable_x)) && target_x="${usable_x}"
  ((target_x > max_x)) && target_x="${max_x}"
  ((target_y < usable_y)) && target_y="${usable_y}"
  ((target_y > max_y)) && target_y="${max_y}"

  # shellcheck disable=SC2178
  local -n out_x_ref="${out_x_name}"
  # shellcheck disable=SC2178
  local -n out_y_ref="${out_y_name}"
  out_x_ref="${target_x}"
  out_y_ref="${target_y}"
}

apply_window_geometry() {
  local window_address="$1"
  local width_spec="$2"
  local height_spec="$3"
  local align="${4:-}"
  local current_width=""
  local current_height=""
  local is_floating=""
  local padded_width=""
  local padded_height=""
  local target_width=""
  local target_height=""
  local usable_x=""
  local usable_y=""
  local usable_width=""
  local usable_height=""
  local target_x=""
  local target_y=""
  local workspace_name=""
  local clamped_width=""
  local clamped_height=""

  launch_geometry_requested "${width_spec}" "${height_spec}" "${align}" || return 0

  launch_read_window_geometry_state "${window_address}" current_width current_height is_floating workspace_name || return 1
  launch_monitor_usable_geometry padded_width padded_height usable_x usable_y usable_width usable_height || return 1
  launch_target_window_size "${current_width}" "${current_height}" "${width_spec}" "${height_spec}" \
    "${padded_width}" "${padded_height}" target_width target_height || return 1
  [[ -n "${align}" ]] || align="center"

  launch_ensure_window_floating "${window_address}" "${is_floating}" || return 1
  launch_read_window_geometry_state "${window_address}" current_width current_height is_floating workspace_name || return 1

  if [[ -n "${width_spec}" || -n "${height_spec}" ]]; then
    launch_resize_window_exact "${window_address}" "${target_width}" "${target_height}" || return 1
    launch_read_window_geometry_state "${window_address}" current_width current_height is_floating workspace_name || return 1
  fi

  if ((current_width > usable_width || current_height > usable_height)); then
    launch_clamp_window_size_to_usable_area "${current_width}" "${current_height}" "${usable_width}" "${usable_height}" \
      clamped_width clamped_height
    launch_resize_window_exact "${window_address}" "${clamped_width}" "${clamped_height}" || return 1
    launch_read_window_geometry_state "${window_address}" current_width current_height is_floating workspace_name || return 1
  fi

  launch_compute_target_position "${align}" "${usable_x}" "${usable_y}" "${usable_width}" "${usable_height}" \
    "${current_width}" "${current_height}" target_x target_y || return 1

  hyprctl -q --batch \
    "dispatch movewindowpixel exact ${target_x} ${target_y},address:${window_address}; \
dispatch focuswindow address:${window_address}" \
    >/dev/null 2>&1
}

main() {
  local use_empty_workspace=0
  local width_spec=""
  local height_spec=""
  local align=""
  local window_pattern=""
  local target_workspace=""
  local window_address=""
  local launch_cmd=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --empty-workspace-if-occupied)
        use_empty_workspace=1
        shift
        ;;
      --width)
        width_spec="$2"
        shift 2
        ;;
      --height)
        height_spec="$2"
        shift 2
        ;;
      --align)
        align="$2"
        shift 2
        ;;
      --)
        shift
        launch_cmd=("$@")
        break
        ;;
      -*)
        usage >&2
        return 1
        ;;
      *)
        window_pattern="$1"
        shift
        ;;
    esac
  done

  [[ -n "${window_pattern}" && "${#launch_cmd[@]}" -gt 0 ]] || {
    usage >&2
    return 1
  }

  window_address="$(launch_resolve_window_address "${window_pattern}")"
  target_workspace="$(launch_prepare_target_workspace "${use_empty_workspace}" "${window_address}")"
  [[ -n "${target_workspace}" ]] || return 1

  if [[ -z "${window_address}" ]]; then
    setsid "${launch_cmd[@]}" >/dev/null 2>&1 &
    window_address="$(launch_wait_for_window_address "${window_pattern}")"
    [[ -n "${window_address}" ]] || return 1
  fi

  summon_window_to_workspace "${window_address}" "${target_workspace}" || return 1
  apply_window_geometry "${window_address}" "${width_spec}" "${height_spec}" "${align}" || return 1
}

main "$@"
