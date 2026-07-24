#!/usr/bin/env bash
#
# summon.sh — Move a matching window to the current/empty workspace and apply optional geometry; spawn it if missing.
#
# Usage: hyprshell launch/summon.sh [options] <window-pattern> -- <command> [args...]
#
# Depends on: hyprctl, setsid, launch/window.common.bash, runtime/init.bash (for print_log)
#
set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/launch/window.common.bash" || exit 1

usage() {
  cat <<'EOF'
Usage: hyprshell launch/summon.sh [options] <window-pattern> -- <command> [args...]

Window pattern may be plain text, class:<class-pattern>, or title:<title-pattern>.

Options:
  --empty-workspace-if-occupied  Use the nearest empty workspace when the current
                                 workspace already contains another tiled window
  --width SPEC                   Target width in px or percent
  --height SPEC                  Target height in px or percent
  --profile NAME                 Target a named window geometry profile
  --align left|right|center      Horizontal placement after summon/resize
EOF
}

launch_summon_to_workspace() {
  local window_address="$1"
  local workspace_name="$2"
  local window_lua=""
  local workspace_lua=""

  launch_source_core_common || return 1
  window_lua="$(hypr_lua_quote "address:${window_address}")"
  workspace_lua="$(hypr_lua_quote "${workspace_name}")"
  hypr_lua_batch \
    "hl.dsp.window.move({workspace=${workspace_lua}, window=${window_lua}, silent=true})" \
    "hl.dsp.focus({window=${window_lua}})" \
    >/dev/null 2>&1
}

launch_geometry_requested() {
  [[ -n "${1:-}" || -n "${2:-}" || -n "${3:-}" ]]
}

launch_window_geometry_state() {
  local window_address="$1"
  local window_info=""

  window_info="$(launch_wait_for_window_info_stable "${window_address}")"
  [[ -n "${window_info}" ]] || return 1
  printf '%s\n' "${window_info}"
}

launch_target_window_size() {
  local current_width="$1"
  local current_height="$2"
  local width_spec="$3"
  local height_spec="$4"
  local padded_width="$5"
  local padded_height="$6"
  local target_width="${current_width}"
  local target_height="${current_height}"

  [[ -n "${width_spec}" ]] && target_width="$(launch_resolve_dimension "${width_spec}" "${padded_width}")"
  [[ -n "${height_spec}" ]] && target_height="$(launch_resolve_dimension "${height_spec}" "${padded_height}")"
  printf '%s\t%s\n' "${target_width}" "${target_height}"
}

launch_ensure_window_floating() {
  local window_address="$1"
  local is_floating="$2"

  [[ "${is_floating}" == "true" ]] && return 0
  launch_source_core_common || return 1
  hypr_lua_dispatch "hl.dsp.window.float({window=$(hypr_lua_quote "address:${window_address}"), action=\"toggle\"})" >/dev/null 2>&1
}

launch_resize_window_exact() {
  local window_address="$1"
  local target_width="$2"
  local target_height="$3"

  launch_source_core_common || return 1
  hypr_lua_dispatch \
    "hl.dsp.window.resize({x=${target_width}, y=${target_height}, exact=true, window=$(hypr_lua_quote "address:${window_address}")})" \
    >/dev/null 2>&1
}

launch_clamp_window_size_to_usable_area() {
  local current_width="$1"
  local current_height="$2"
  local usable_width="$3"
  local usable_height="$4"
  local target_width="${current_width}"
  local target_height="${current_height}"

  ((current_width > usable_width)) && target_width="${usable_width}"
  ((current_height > usable_height)) && target_height="${usable_height}"
  printf '%s\t%s\n' "${target_width}" "${target_height}"
}

launch_compute_target_position() {
  local align="${1:-center}"
  local usable_x="$2"
  local usable_y="$3"
  local usable_width="$4"
  local usable_height="$5"
  local current_width="$6"
  local current_height="$7"
  local max_x=""
  local max_y=""
  local target_x=""
  local target_y=""

  max_x=$((usable_x + usable_width - current_width))
  max_y=$((usable_y + usable_height - current_height))
  ((max_x >= usable_x)) || max_x="${usable_x}"
  ((max_y >= usable_y)) || max_y="${usable_y}"

  case "${align}" in
    left)   target_x="${usable_x}" ;;
    right)  target_x="${max_x}"    ;;
    center) target_x=$((usable_x + (usable_width - current_width) / 2)) ;;
    *)
      print_log -sec "summon" -err "align" "Unknown align value: ${align}"
      return 1
      ;;
  esac

  target_y=$((usable_y + (usable_height - current_height) / 2))
  ((target_x < usable_x)) && target_x="${usable_x}"
  ((target_x > max_x)) && target_x="${max_x}"
  ((target_y < usable_y)) && target_y="${usable_y}"
  ((target_y > max_y)) && target_y="${max_y}"

  printf '%s\t%s\n' "${target_x}" "${target_y}"
}

#? Splits the resize/clamp half of the geometry pipeline from the position half.
#? Re-reads window state after each mutation so the caller sees the post-resize size.
launch_apply_window_size() {
  local window_address="$1"
  local width_spec="$2"
  local height_spec="$3"
  local padded_width="$4"
  local padded_height="$5"
  local usable_width="$6"
  local usable_height="$7"
  local current_width=""
  local current_height=""
  local is_floating=""
  local _workspace_name=""
  local target_width=""
  local target_height=""
  local clamped_width=""
  local clamped_height=""

  IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
    < <(launch_window_geometry_state "${window_address}") || return 1
  IFS=$'\t' read -r target_width target_height \
    < <(launch_target_window_size "${current_width}" "${current_height}" "${width_spec}" "${height_spec}" \
      "${padded_width}" "${padded_height}") || return 1

  launch_ensure_window_floating "${window_address}" "${is_floating}" || return 1
  IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
    < <(launch_window_geometry_state "${window_address}") || return 1

  if [[ -n "${width_spec}" || -n "${height_spec}" ]]; then
    launch_resize_window_exact "${window_address}" "${target_width}" "${target_height}" || return 1
    IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
      < <(launch_window_geometry_state "${window_address}") || return 1
  fi

  if ((current_width > usable_width || current_height > usable_height)); then
    IFS=$'\t' read -r clamped_width clamped_height \
      < <(launch_clamp_window_size_to_usable_area "${current_width}" "${current_height}" "${usable_width}" "${usable_height}") || return 1
    launch_resize_window_exact "${window_address}" "${clamped_width}" "${clamped_height}" || return 1
    IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
      < <(launch_window_geometry_state "${window_address}") || return 1
  fi

  printf '%s\t%s\n' "${current_width}" "${current_height}"
}

launch_apply_window_position() {
  local window_address="$1"
  local align="$2"
  local current_width="$3"
  local current_height="$4"
  local usable_x="$5"
  local usable_y="$6"
  local usable_width="$7"
  local usable_height="$8"
  local target_x=""
  local target_y=""
  local window_lua=""

  IFS=$'\t' read -r target_x target_y \
    < <(launch_compute_target_position "${align}" "${usable_x}" "${usable_y}" "${usable_width}" "${usable_height}" \
      "${current_width}" "${current_height}") || return 1

  launch_source_core_common || return 1
  window_lua="$(hypr_lua_quote "address:${window_address}")"
  hypr_lua_batch \
    "hl.dsp.window.move({x=${target_x}, y=${target_y}, exact=true, window=${window_lua}})" \
    "hl.dsp.focus({window=${window_lua}})" \
    >/dev/null 2>&1
}

launch_apply_window_geometry() {
  local window_address="$1"
  local width_spec="$2"
  local height_spec="$3"
  local align="${4:-}"
  local current_width=""
  local current_height=""
  local padded_width=""
  local padded_height=""
  local usable_x=""
  local usable_y=""
  local usable_width=""
  local usable_height=""

  launch_geometry_requested "${width_spec}" "${height_spec}" "${align}" || return 0
  [[ -n "${align}" ]] || align="center"

  IFS=$'\t' read -r padded_width padded_height usable_x usable_y usable_width usable_height \
    < <(launch_monitor_usable_geometry) || return 1
  IFS=$'\t' read -r current_width current_height \
    < <(launch_apply_window_size "${window_address}" "${width_spec}" "${height_spec}" \
      "${padded_width}" "${padded_height}" "${usable_width}" "${usable_height}") || return 1
  launch_apply_window_position "${window_address}" "${align}" \
    "${current_width}" "${current_height}" \
    "${usable_x}" "${usable_y}" "${usable_width}" "${usable_height}" || return 1
}

main() {
  local use_empty_workspace=0
  local width_spec=""
  local height_spec=""
  local geometry_profile=""
  local align=""
  local window_pattern=""
  local target_workspace=""
  local window_address=""
  local launch_cmd=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --empty-workspace-if-occupied) use_empty_workspace=1; shift ;;
      --width)  width_spec="$2";  shift 2 ;;
      --height) height_spec="$2"; shift 2 ;;
      --profile) geometry_profile="$2"; shift 2 ;;
      --align)  align="$2";       shift 2 ;;
      --)
        shift
        launch_cmd=("$@")
        break
        ;;
      -*)
        usage >&2
        return 2
        ;;
      *)
        window_pattern="$1"
        shift
        ;;
    esac
  done

  [[ -n "${window_pattern}" && "${#launch_cmd[@]}" -gt 0 ]] || {
    usage >&2
    return 2
  }

  if [[ -n "${geometry_profile}" ]]; then
    if [[ -n "${width_spec}" || -n "${height_spec}" ]]; then
      print_log -sec "summon" -err "geometry" "--profile cannot be combined with --width or --height"
      return 2
    fi
    IFS=$'\t' read -r width_spec height_spec \
      <<<"$(launch_resolve_geometry_profile "${geometry_profile}")" || return 1
  fi

  window_address="$(launch_resolve_window_address "${window_pattern}")"
  target_workspace="$(launch_prepare_target_workspace "${use_empty_workspace}" "${window_address}")"
  [[ -n "${target_workspace}" ]] || return 1

  if [[ -z "${window_address}" ]]; then
    setsid "${launch_cmd[@]}" >/dev/null 2>&1 &
    window_address="$(launch_wait_for_window_address "${window_pattern}")"
    [[ -n "${window_address}" ]] || return 1
  fi

  launch_summon_to_workspace "${window_address}" "${target_workspace}" || return 1
  launch_apply_window_geometry "${window_address}" "${width_spec}" "${height_spec}" "${align}" || return 1
}

main "$@"
