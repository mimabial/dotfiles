#!/usr/bin/env bash

# Early load to maintain fastfetch speed
if [ -z "${*}" ]; then
  clear
  exec fastfetch --logo-type kitty
  exit
fi

USAGE() {
  cat <<USAGE
Usage: fastfetch [commands] [options]

commands:
  logo    Display a random logo

options:
  -S, --select    Select a logo from the local fastfetch logo library
  -h, --help,     Display command's help message

USAGE
}

# Source state and os-release
# shellcheck source=/dev/null
[ -f "$HYPR_STATE_HOME/staterc" ] && source "$HYPR_STATE_HOME/staterc"
# shellcheck disable=SC1091
[ -f "/etc/os-release" ] && source "/etc/os-release"

# Set the variables
iconDir="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
FASTFETCH_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
FASTFETCH_CONFIG_FILE="${FASTFETCH_CONFIG_HOME}/config.jsonc"
FASTFETCH_LOGO_DIR="${FASTFETCH_CONFIG_HOME}/logo"
HYPR_CACHE_HOME="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
WALLPAPER_CURRENT_DIR="${WALLPAPER_CURRENT_DIR:-${HYPR_CACHE_HOME}/wallpaper/current}"
image_dirs=()
distro_logo=${iconDir}/Pywal16-Icon/distro/$LOGO

expand_home_tokens() {
  local path="${1:-}"
  path="${path//\$HOME/${HOME}}"
  path="${path//\$\{HOME\}/${HOME}}"
  printf '%s\n' "${path}"
}

compact_home_path() {
  local path="${1:-}"
  if [[ "${path}" == "${HOME}"* ]]; then
    printf '$HOME%s\n' "${path#"${HOME}"}"
    return 0
  fi

  printf '%s\n' "${path}"
}

fastfetch_current_logo_source() {
  local source_path

  [[ -f "${FASTFETCH_CONFIG_FILE}" ]] || return 1

  source_path="$(
    sed -nE 's/^[[:space:]]*"source"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${FASTFETCH_CONFIG_FILE}" | head -n 1
  )"
  [[ -n "${source_path}" ]] || return 1
  expand_home_tokens "${source_path}"
}

fastfetch_list_logo_library() {
  [[ -d "${FASTFETCH_LOGO_DIR}" ]] || return 0
  find -L "${FASTFETCH_LOGO_DIR}" -maxdepth 1 -type f -print0 2>/dev/null | sort -z
}

fastfetch_logo_label() {
  local logo_path="$1"
  local base_name display_name

  base_name="$(basename "${logo_path}")"
  display_name="${base_name%.*}"
  display_name="${display_name//_/ }"
  display_name="${display_name//-/ }"
  printf '%s\n' "${display_name}"
}

fastfetch_select_logo_ui() {
  local current_label="$1"
  shift
  local -a labels=("$@")
  local selected_label=""

  if command -v rofi >/dev/null 2>&1 && { [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ -n "${DISPLAY:-}" ]]; }; then
    if [[ -n "${current_label}" ]]; then
      selected_label="$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "Fastfetch logo" -select "${current_label}")"
    else
      selected_label="$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "Fastfetch logo")"
    fi
  elif command -v fzf >/dev/null 2>&1; then
    selected_label="$(printf '%s\n' "${labels[@]}" | fzf --prompt="Fastfetch logo > " --reverse --select-1 --query="${current_label}")"
  else
    printf 'Error: rofi or fzf is required for --select\n' >&2
    return 1
  fi

  [[ -n "${selected_label}" ]] || return 1
  printf '%s\n' "${selected_label}"
}

fastfetch_set_logo_source() {
  local source_path="$1"
  local compact_path escaped_path

  [[ -f "${FASTFETCH_CONFIG_FILE}" ]] || {
    printf 'Error: fastfetch config not found at %s\n' "${FASTFETCH_CONFIG_FILE}" >&2
    return 1
  }

  compact_path="$(compact_home_path "${source_path}")"
  escaped_path="$(printf '%s' "${compact_path}" | sed 's/[&|\\]/\\&/g')"
  sed -i "0,/\"source\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/s|\"source\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"source\": \"${escaped_path}\"|" "${FASTFETCH_CONFIG_FILE}"
}

fastfetch_select_logo() {
  local selected_label current_source current_label selected_path
  local -a logo_paths=()
  local -a logo_labels=()
  local index

  while IFS= read -r -d '' selected_path; do
    logo_paths+=("${selected_path}")
    logo_labels+=("$(fastfetch_logo_label "${selected_path}")")
  done < <(fastfetch_list_logo_library)

  ((${#logo_paths[@]} > 0)) || {
    printf 'Error: no fastfetch logos found in %s\n' "${FASTFETCH_LOGO_DIR}" >&2
    return 1
  }

  current_source="$(fastfetch_current_logo_source 2>/dev/null || true)"
  for index in "${!logo_paths[@]}"; do
    if [[ "${logo_paths[${index}]}" == "${current_source}" ]]; then
      current_label="${logo_labels[${index}]}"
      break
    fi
  done

  selected_label="$(fastfetch_select_logo_ui "${current_label:-}" "${logo_labels[@]}")" || return 1

  selected_path=""
  for index in "${!logo_labels[@]}"; do
    if [[ "${logo_labels[${index}]}" == "${selected_label}" ]]; then
      selected_path="${logo_paths[${index}]}"
      break
    fi
  done

  [[ -n "${selected_path:-}" ]] || {
    printf 'Error: selected fastfetch logo could not be resolved\n' >&2
    return 1
  }

  fastfetch_set_logo_source "${selected_path}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Fastfetch" "Logo set to ${selected_label}" >/dev/null 2>&1 || true
  fi
  printf '%s\n' "${selected_path}"
}

# Parse the main command
case $1 in
  logo) # eats around 13 ms
    random() {
      (
        image_dirs+=("${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/logo")
        image_dirs+=("${iconDir}/Pywal16-Icon/fastfetch/")
        if [ -n "${HYPR_THEME}" ] && [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${HYPR_THEME}/logo" ]; then
          image_dirs+=("${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${HYPR_THEME}/logo")
        fi
        # [ -d "${HYPR_CACHE_HOME}" ] && image_dirs+=("${HYPR_CACHE_HOME}")
        [ -f "$distro_logo" ] && echo "${distro_logo}"
        image_dirs+=("$WALLPAPER_CURRENT_DIR/wall.quad")
        image_dirs+=("$WALLPAPER_CURRENT_DIR/wall.sqre")
        [ -f "$HOME/.face.icon" ] && image_dirs+=("$HOME/.face.icon")
        # also .bash_logout may be matched with this find
        find -L "${image_dirs[@]}" -maxdepth 1 -type f \( -name "wall.quad" -o -name "wall.sqre" -o -name "*.icon" -o -name "*logo*" -o -name "*.png" \) ! -path "*/wall.set*" ! -path "*/wallpaper/current/*.png" ! -path "*/wallpapers/*.png" 2>/dev/null
      ) | shuf -n 1
    }
    help() {
      cat <<HELP
Usage: ${0##*/} logo [option]

options:
  --quad    Display a quad wallpaper logo
  --sqre    Display a square wallpaper logo
  --prof    Display your profile picture (~/.face.icon)
  --os      Display the distro logo
  --local   Display a logo inside the fastfetch logo directory
  --wall    Display a logo inside the pywal16 fastfetch directory
  --theme   Display a logo inside the theme directory
  --rand    Display a random logo
  *         Display a random logo
  *help*    Display this help message

Note: Options can be combined to search across multiple sources
Example: ${0##*/} logo --local --os --prof
HELP
    }

    # Parse the logo options
    shift
    [ -z "${*}" ] && random && exit
    [[ "$1" = "--rand" ]] && random && exit
    [[ "$1" = *"help"* ]] && help && exit
    (
      image_dirs=()
      for arg in "$@"; do
        case $arg in
          --quad)
            image_dirs+=("$WALLPAPER_CURRENT_DIR/wall.quad")
            ;;
          --sqre)
            image_dirs+=("$WALLPAPER_CURRENT_DIR/wall.sqre")
            ;;
          --prof)
            [ -f "$HOME/.face.icon" ] && image_dirs+=("$HOME/.face.icon")
            ;;
          --os)
            [ -f "$distro_logo" ] && image_dirs+=("$distro_logo")
            ;;
          --local)
            image_dirs+=("${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/logo")
            ;;
          --wall)
            image_dirs+=("${iconDir}/Pywal16-Icon/fastfetch/")
            ;;
          --theme)
            if [ -n "${HYPR_THEME}" ] && [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${HYPR_THEME}/logo" ]; then
              image_dirs+=("${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${HYPR_THEME}/logo")
            fi
            ;;
        esac
      done
      find -L "${image_dirs[@]}" -maxdepth 1 -type f \( -name "wall.quad" -o -name "wall.sqre" -o -name "*.icon" -o -name "*logo*" -o -name "*.png" \) ! -path "*/wall.set*" ! -path "*/wallpaper/current/*.png" ! -path "*/wallpapers/*.png" 2>/dev/null
    ) | shuf -n 1

    ;;
  --select | -S)
    fastfetch_select_logo

    ;;
  help | --help | -h)
    USAGE
    ;;
  *)
    clear
    exec fastfetch --logo-type kitty
    ;;
esac
