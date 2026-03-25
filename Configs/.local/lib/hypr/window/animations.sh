#!/usr/bin/env bash

# shellcheck source=$HOME/.local/bin/hyprshell
# shellcheck disable=SC1091
if ! source "$(command -v hyprshell)"; then
  echo "[$0] :: Error: hyprshell not found."
  exit 1
fi
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"

animations_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/animations"
animations_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/animations"
animations_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/animations.conf"

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]

Options:
    --select | -S       Select an animation from the available options
    --reload | -r       Reload the current animation
    --help   | -h       Show this help message
HELP
}

resolve_animation_path() {
  local name="${1:-theme}"
  name="${name%.conf}"

  if [[ "${name}" == */* ]] && [[ -f "${name}" ]]; then
    printf '%s\n' "${name}"
    return 0
  fi

  local candidate
  for candidate in \
    "${animations_user_dir}/${name}.conf" \
    "${animations_shared_dir}/${name}.conf"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

list_animation_names() {
  local dir path name
  local -A seen=()

  for dir in "${animations_user_dir}" "${animations_shared_dir}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r -d '' path; do
      name="$(basename "${path}" .conf)"
      [[ "${name}" == "disable" || "${name}" == "theme" ]] && continue
      [[ -n "${seen[${name}]:-}" ]] && continue
      seen["${name}"]=1
      printf '%s\n' "${name}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name '*.conf' -print0 | sort -z)
  done
}

fn_select() {
  local animation_items rofi_select selected_animation
  local -a rofi_args

  animation_items="$(list_animation_names)"
  animation_items=$(printf 'Disable Animation\n%s\n' "${animation_items}" | sed '/^$/d')

  rofi_select="${HYPR_ANIMATION:-default}"
  rofi_select="${rofi_select/disable/Disable Animation}"

  rofi_build_standard_menu_args \
    rofi_args \
    "Select animation" \
    " 󰪏 Animation" \
    "clipboard" \
    "${ROFI_ANIMATION_SCALE}" \
    "${ROFI_ANIMATION_FONT:-$ROFI_FONT}"
  rofi_args+=(-select "${rofi_select}")

  selected_animation=$(printf '%s\n' "${animation_items}" \
    | rofi "${rofi_args[@]}")

  [[ -n "${selected_animation}" ]] || exit 0

  case "${selected_animation}" in
    "Disable Animation") selected_animation="disable" ;;
  esac

  state_set "HYPR_ANIMATION" "${selected_animation}" "staterc"
  fn_update
  send_ephemeral_notif "hypr-animation" -t 2000 -i "preferences-desktop-display" "Animation selected" "${selected_animation}"
}

fn_update() {
  local current_animation animation_path compact_path

  declare -F export_hypr_config >/dev/null && export_hypr_config

  current_animation=${HYPR_ANIMATION:-default}
  animation_path="$(resolve_animation_path "${current_animation}")" || {
    send_ephemeral_notif "hypr-animation-error" -t 3000 -i "preferences-desktop-display" "Error" "Animation '${current_animation}' not found in ${animations_user_dir} or ${animations_shared_dir}"
    return 1
  }

  mkdir -p "$(dirname "${animations_state_file}")"
  compact_path="$(hypr_compact_path "${animation_path}")"

  cat <<CONF >"${animations_state_file}"
#! ▄▀█ █▄░█ █ █▀▄▀█ ▄▀█ ▀█▀ █ █▀█ █▄░█
#! █▀█ █░▀█ █ █░▀░█ █▀█ ░█░ █ █▄█ █░▀█


#*┌────────────────────────────────────────────────────────────────────────────┐
#*│ # System controlled content // DO NOT EDIT                                │
#*│ # User overrides live in ~/.config/hypr/animations/                       │
#*│ # Shared stock lives in ~/.local/share/hypr/animations/                   │
#*│ # Run 'hyprshell window/animations.sh --select' to change the current one │
#*└────────────────────────────────────────────────────────────────────────────┘

\$ANIMATION=${current_animation}
\$ANIMATION_PATH=${compact_path}
source = \$ANIMATION_PATH
CONF
}

fn_reload() {
  local animation_name="${HYPR_ANIMATION:-default}"
  state_set "HYPR_ANIMATION" "${animation_name}" "staterc"
  fn_update
  send_ephemeral_notif "hypr-animation" -t 2000 -i "preferences-desktop-display" "Animation reloaded" "${animation_name}"
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
  exit 1
fi

LONGOPTS="select,reload,help"
PARSED=$(getopt --options Srh --longoptions "${LONGOPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

while true; do
  case "$1" in
    -S | --select)
      fn_select
      exit 0
      ;;
    -r | --reload)
      fn_reload
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
