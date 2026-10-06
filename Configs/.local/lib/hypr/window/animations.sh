#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/window/stateful-choice.common.bash"

animations_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/animations"
animations_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/animations"
animations_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/animations.lua"

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]
Set or reload the active Hyprland animation preset.

Options:
    --set NAME          Set an animation
    --list              List selectable animations as name, icon and description
    --reload | -r       Reload the current animation
    --help   | -h       Show this help message
HELP
}

resolve_animation_path() {
  local name="${1:-theme}"
  name="${name%.lua}"
  hypr_stateful_choice_resolve_path "${name}" "lua" "${animations_user_dir}" "${animations_shared_dir}"
}

list_animation_names() {
  hypr_stateful_choice_list_names "lua" "${animations_user_dir}" "${animations_shared_dir}" "disable" "theme"
}

# Keep workflow-compatible tab-separated fields, including empty metadata.
list_animations() {
  local name=""
  {
    printf 'disable\n'
    list_animation_names
  } | sed '/^$/d' | while IFS= read -r name; do
    printf '%s\t\t\n' "${name}"
  done
}

write_animation_state() {
  local current_animation animation_path

  current_animation="${1:-$(state_get "HYPR_ANIMATION" "default")}"
  animation_path="$(resolve_animation_path "${current_animation}")" || {
    send_ephemeral_notif "hypr-animation-error" -t 3000 -i "preferences-desktop-display" "Error" "Animation '${current_animation}' not found in ${animations_user_dir} or ${animations_shared_dir}"
    return 1
  }

  hypr_stateful_choice_write_lua "${animations_state_file}" \
    --load "${animation_path}" \
    "ANIMATION=${current_animation}" \
    "ANIMATION_PATH=${animation_path}"
}

reload_animation() {
  local animation_name
  animation_name="$(state_get "HYPR_ANIMATION" "default")"
  apply_animation "${animation_name}" "Animation reloaded"
}

apply_animation() {
  local animation_name="$1"
  local notification_title="$2"

  resolve_animation_path "${animation_name}" >/dev/null || {
    echo "Error: unknown animation '${animation_name}'" >&2
    return 1
  }
  hypr_stateful_choice_apply "HYPR_ANIMATION" "${animation_name}" "hypr-animation" "${notification_title}" write_animation_state
  hyprctl reload config-only -q
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
  exit 1
fi

LONGOPTS="set:,list,reload,help"
PARSED=$(getopt --options rh --longoptions "${LONGOPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

while true; do
  case "$1" in
    --set)
      [[ -n "${2:-}" ]] || {
        echo "Error: --set requires an animation name" >&2
        exit 1
      }
      apply_animation "$2" "Animation selected"
      exit 0
      ;;
    --list)
      list_animations
      exit 0
      ;;
    -r | --reload)
      reload_animation
      exit 0
      ;;
    --help | -h)
      show_help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option: $1"
      show_help
      exit 1
      ;;
  esac
done
