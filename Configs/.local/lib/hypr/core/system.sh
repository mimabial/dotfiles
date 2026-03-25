#!/usr/bin/env bash
# shellcheck disable=SC1091,SC1090

# ============================================================================
# pkg_installed - Check if a package is installed
# ============================================================================
# Arguments:
#   $1 - Package name to check
# Returns:
#   0 - Package is installed (via command, flatpak, or package manager)
#   1 - Package is not installed or invalid input
# Example:
#   if pkg_installed "rofi"; then
#     echo "rofi is available"
#   fi
pkg_installed() {
  local pkgIn="${1}"

  # Validate input
  if [[ -z "${pkgIn}" ]]; then
    return 1
  fi

  if command -v "${pkgIn}" &>/dev/null; then
    return 0
  elif command -v "flatpak" &>/dev/null && flatpak info "${pkgIn}" &>/dev/null; then
    return 0
  elif hyprshell pm.sh pq "${pkgIn}" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

get_aur_helper() {
  if pkg_installed yay; then
    aur_helper="yay"
  elif pkg_installed paru; then
    # shellcheck disable=SC2034
    aur_helper="paru"
  fi
}

# ============================================================================
# get_hypr_conf - Get a variable value from Hyprland theme config
# ============================================================================
# Arguments:
#   $1 - Variable name (without $ prefix)
#   $2 - Config file path (optional, defaults to current theme's hypr.theme)
# Output:
#   Prints variable value to stdout
# Returns:
#   0 - Variable found
#   1 - Variable not found or invalid input
# Notes:
#   - Tries hyq first for fast parsing, falls back to grep/awk
#   - Checks theme file, then gsettings execs, then defaults
# Example:
#   gtk_theme=$(get_hypr_conf "GTK_THEME")
get_hypr_conf() {
  local hyVar="${1}"
  local file="${2:-"$HYPR_THEME_DIR/hypr.theme"}"
  local value=""
  local defaults_file=""

  if [[ -z "${hyVar}" ]]; then
    return 1
  fi

  if [[ ! -r "${file}" ]]; then
    return 1
  fi

  if command -v hyq &>/dev/null; then
    value="$(hyq --query "\$${hyVar}" "${file}" 2>/dev/null || true)"
    [ -n "${value}" ] && printf '%s\n' "${value}" && return 0
  fi

  value="$(awk -F'=' -v key="\$${hyVar}" '
    /^[[:space:]]*#/ { next }
    {
      lhs = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
      if (lhs == key) {
        sub(/^[^=]*=/, "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }
  ' "${file}")"
  if [[ -n "${value}" ]] && [[ "${value}" != \$* ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  defaults_file="$(hypr_variables_file)"
  if [[ -f "${defaults_file}" ]]; then
    awk -F'=' -v key="\$default.${hyVar}" '
      /^[[:space:]]*#/ { next }
      {
        lhs = $1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
        if (lhs == key) {
          sub(/^[^=]*=/, "", $0)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
          print $0
          exit
        }
      }
    ' "${defaults_file}"
  fi
}

#? handle pasting
paste_string() {
  if ! command -v wtype >/dev/null; then exit 0; fi
  if [ -t 1 ]; then return 0; fi
  ignore_paste_file="$HYPR_STATE_HOME/ignore.paste"

  if [[ ! -e "${ignore_paste_file}" ]]; then
    cat <<EOF >"${ignore_paste_file}"
kitty
org.kde.konsole
terminator
XTerm
Alacritty
xterm-256color
EOF
  fi

  ignore_class="${*#*--ignore=}"
  [[ "$*" != *--ignore=* ]] && ignore_class=""
  [ -n "${ignore_class}" ] && echo "${ignore_class}" >>"${ignore_paste_file}" && print_log -y "[ignore]" "'$ignore_class'" && exit 0
  class=$(hyprctl -j activewindow | jq -r '.initialClass')
  if ! grep -q "${class}" "${ignore_paste_file}"; then
    hyprctl -q dispatch exec 'wtype -M ctrl V -m ctrl'
  fi
}

#? Checks if the cursor is hovered on a window
is_hovered() {
  data=$(hyprctl --batch -j "cursorpos;activewindow" | jq -s '.[0] * .[1]')
  # evaluate the output of the JSON data into shell variables
  eval "$(echo "$data" | jq -r '@sh "cursor_x=\(.x // 0) cursor_y=\(.y // 0) window_x=\(.at[0] // 0) window_y=\(.at[1] // 0) window_size_x=\(.size[0] // 0) window_size_y=\(.size[1] // 0)"')"
  # Check if the cursor is hovered in the active window
  if ((cursor_x >= window_x && cursor_x <= window_x + window_size_x && cursor_y >= window_y && cursor_y <= window_y + window_size_y)); then
    return 0
  fi
  return 1
}

# ============================================================================
# toml_write - Write a key=value pair to a TOML/INI config file
# ============================================================================
# Arguments:
#   $1 - Config file path
#   $2 - Group/section name (e.g., "General", "Colors:View")
#   $3 - Key name
#   $4 - Value to write
# Returns:
#   0 - Always succeeds
# Notes:
#   - Uses kwriteconfig6 if available, falls back to sed
#   - Creates group section if it doesn't exist
# Example:
#   toml_write "$HOME/.config/kdeglobals" "Icons" "Theme" "Papirus"
toml_write() {
  local config_file="${1}"
  local group="${2}"
  local key="${3}"
  local value="${4}"

  # Validate inputs
  [[ -z "${config_file}" ]] && return 1
  [[ -z "${group}" ]] && return 1
  [[ -z "${key}" ]] && return 1

  if ! kwriteconfig6 --file "${config_file}" --group "${group}" --key "${key}" "${value}" 2>/dev/null; then
    if ! grep -q "^\[${group}\]" "${config_file}"; then
      echo -e "\n[${group}]\n${key}=${value}" >>"${config_file}"
    elif ! grep -q "^${key}=" "${config_file}"; then
      sed -i "/^\[${group}\]/a ${key}=${value}" "${config_file}"
    fi
  fi
}
