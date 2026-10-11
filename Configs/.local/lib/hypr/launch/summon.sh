#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/launch/lib/window-launch.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/launch/lib/summoned-window-geometry.bash" || exit 1

usage() {
  cat <<'EOF'
Usage: hyprshell launch/summon.sh [options] <window-pattern> -- <command> [args...]

Window pattern may be plain text, class:<class-pattern>, or title:<title-pattern>.

Options:
  --empty-workspace-if-occupied  Use the nearest empty workspace when the current
                                 workspace already contains another window
  --float-if-workspace-occupied Float when the current workspace contains another
                                 window; otherwise tile
  --tile                         Keep the summoned window tiled, overriding an
                                 initial floating window rule
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

parse_summon_arguments() {
  local -n options_ref="$1"
  local -n command_ref="$2"
  shift 2

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --empty-workspace-if-occupied) options_ref[empty_workspace]=1; shift ;;
      --float-if-workspace-occupied) options_ref[float_if_occupied]=1; shift ;;
      --tile) options_ref[tile]=1; shift ;;
      --width)   options_ref[width]="$2";   shift 2 ;;
      --height)  options_ref[height]="$2";  shift 2 ;;
      --profile) options_ref[profile]="$2"; shift 2 ;;
      --align)   options_ref[align]="$2";   shift 2 ;;
      --)
        shift
        command_ref=("$@")
        break
        ;;
      -*) return 2 ;;
      *)
        options_ref[pattern]="$1"
        shift
        ;;
    esac
  done

  [[ -n "${options_ref[pattern]}" && "${#command_ref[@]}" -gt 0 ]]
}

summon_resolve_geometry() {
  local -n geometry_ref="$1"
  local profile_size=""

  if [[ -n "${geometry_ref[profile]}" ]]; then
    if [[ -n "${geometry_ref[width]}${geometry_ref[height]}" ]]; then
      print_log -sec "summon" -err "geometry" "--profile cannot be combined with --width or --height"
      return 2
    fi
    profile_size="$(launch_resolve_geometry_profile "${geometry_ref[profile]}")" || return 1
    IFS=$'\t' read -r "geometry_ref[width]" "geometry_ref[height]" <<<"${profile_size}"
  fi

  if ((geometry_ref[tile] == 1)) \
    && launch_geometry_requested "${geometry_ref[width]}" "${geometry_ref[height]}" "${geometry_ref[align]}"; then
    print_log -sec "summon" -err "geometry" "--tile cannot be combined with floating-window geometry"
    return 2
  fi
}

main() {
  [[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; return; }

  local -A options=(
    [empty_workspace]=0 [float_if_occupied]=0 [tile]=0
    [width]="" [height]="" [profile]="" [align]="" [pattern]=""
  )
  local -a launch_cmd=()
  local target_workspace=""
  local window_address=""
  local hypr_snapshot_json=""
  local clients_json=""
  local workspace_has_other_window="false"

  parse_summon_arguments options launch_cmd "$@" || {
    usage >&2
    return 2
  }

  hypr_snapshot_json="$(hyprctl --batch -j 'activeworkspace;clients;monitors all' | jq -sc '.')"
  clients_json="$(jq -c '.[1] // []' <<<"${hypr_snapshot_json}")"
  hypr_monitors_json_prime "$(jq -c '.[2] // []' <<<"${hypr_snapshot_json}")"

  summon_resolve_geometry options || return $?

  window_address="$(launch_resolve_window_address "${options[pattern]}" "${clients_json}")"
  if ((options[float_if_occupied] == 1)); then
    IFS=$'\t' read -r _ workspace_has_other_window \
      < <(launch_active_workspace_occupancy "${window_address}" "${hypr_snapshot_json}") || return 1
  fi
  target_workspace="$(launch_prepare_target_workspace "${options[empty_workspace]}" "${window_address}" "${hypr_snapshot_json}")"
  [[ -n "${target_workspace}" ]] || return 1

  if [[ -z "${window_address}" ]]; then
    setsid hyprshell app -- "${launch_cmd[@]}" >/dev/null 2>&1 &
    window_address="$(launch_wait_for_window_address "${options[pattern]}")"
    [[ -n "${window_address}" ]] || return 1
  fi

  launch_summon_to_workspace "${window_address}" "${target_workspace}" || return 1
  launch_apply_window_geometry "${window_address}" "${options[width]}" "${options[height]}" "${options[align]}" || return 1
  if ((options[float_if_occupied] == 1)) && [[ "${workspace_has_other_window}" == "true" ]]; then
    launch_ensure_window_floating "${window_address}" false || return 1
  elif ((options[float_if_occupied] == 1 || options[tile] == 1)); then
    launch_ensure_window_tiled "${window_address}" || return 1
  fi
}

main "$@"
