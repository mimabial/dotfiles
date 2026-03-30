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

apply_window_geometry() {
  local window_address="$1"
  local width_spec="$2"
  local height_spec="$3"
  local align="${4:-}"
  local current_width=""
  local current_height=""
  local is_floating=""
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
  local padded_width=""
  local padded_height=""
  local target_width=""
  local target_height=""
  local edge_padding=""
  local usable_x=""
  local usable_y=""
  local usable_width=""
  local usable_height=""
  local max_x=""
  local max_y=""
  local target_x=""
  local target_y=""
  local window_info=""

  [[ -n "${width_spec}" || -n "${height_spec}" || -n "${align}" ]] || return 0

  window_info="$(launch_wait_for_window_info_stable "${window_address}")"
  [[ -n "${window_info}" ]] || return 1
  IFS=$'\t' read -r current_width current_height is_floating _ <<<"${window_info}"

  IFS=$'\t' read -r monitor_x monitor_y monitor_width monitor_height reserve_left reserve_top reserve_right reserve_bottom \
    <<<"$(launch_focused_monitor_geometry)"

  visible_width=$((monitor_width - reserve_left - reserve_right))
  visible_height=$((monitor_height - reserve_top - reserve_bottom))
  ((visible_width > 0 && visible_height > 0)) || return 1

  edge_padding="$(launch_window_edge_padding_px)"
  padded_width=$((visible_width - (edge_padding * 2)))
  padded_height=$((visible_height - (edge_padding * 2)))
  ((padded_width > 0)) || padded_width=1
  ((padded_height > 0)) || padded_height=1

  target_width="${current_width}"
  target_height="${current_height}"
  [[ -n "${width_spec}" ]] && target_width="$(launch_resolve_dimension "${width_spec}" "${padded_width}")"
  [[ -n "${height_spec}" ]] && target_height="$(launch_resolve_dimension "${height_spec}" "${padded_height}")"
  [[ -n "${align}" ]] || align="center"

  if [[ "${is_floating}" != "true" ]]; then
    hyprctl dispatch togglefloating "address:${window_address}" >/dev/null 2>&1 || return 1
    window_info="$(launch_wait_for_window_info_stable "${window_address}")"
    [[ -n "${window_info}" ]] || return 1
    IFS=$'\t' read -r current_width current_height is_floating _ <<<"${window_info}"
  fi

  if [[ -n "${width_spec}" || -n "${height_spec}" ]]; then
    hyprctl -q --batch \
      "dispatch resizewindowpixel exact ${target_width} ${target_height},address:${window_address}" \
      >/dev/null 2>&1 || return 1

    window_info="$(launch_wait_for_window_info_stable "${window_address}")"
    [[ -n "${window_info}" ]] || return 1
    IFS=$'\t' read -r current_width current_height _ _ <<<"${window_info}"
  fi

  usable_x=$((monitor_x + reserve_left + edge_padding))
  usable_y=$((monitor_y + reserve_top + edge_padding))
  usable_width=$((monitor_width - reserve_left - reserve_right - (edge_padding * 2)))
  usable_height=$((monitor_height - reserve_top - reserve_bottom - (edge_padding * 2)))
  ((usable_width > 0)) || usable_width=1
  ((usable_height > 0)) || usable_height=1

  if ((current_width > usable_width || current_height > usable_height)); then
    ((current_width > usable_width)) && target_width="${usable_width}" || target_width="${current_width}"
    ((current_height > usable_height)) && target_height="${usable_height}" || target_height="${current_height}"

    hyprctl -q --batch \
      "dispatch resizewindowpixel exact ${target_width} ${target_height},address:${window_address}" \
      >/dev/null 2>&1 || return 1

    window_info="$(launch_wait_for_window_info_stable "${window_address}")"
    [[ -n "${window_info}" ]] || return 1
    IFS=$'\t' read -r current_width current_height _ _ <<<"${window_info}"
  fi

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
