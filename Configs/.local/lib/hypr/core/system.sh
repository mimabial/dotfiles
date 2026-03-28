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

  [[ -n "${pkgIn}" ]] || return 1
  command -v "${pkgIn}" &>/dev/null && return 0
  command -v flatpak &>/dev/null && flatpak info "${pkgIn}" &>/dev/null && return 0
  hyprshell pm.sh pq "${pkgIn}" &>/dev/null
}

escape_regex() {
  printf '%s' "$1" | sed 's/[][(){}.^$?*+|\\/]/\\&/g'
}

sed_escape_append_text() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//$'\n'/\\n}"
  printf '%s' "${value}"
}

sed_escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "${value}"
}

ini_group_has_key() {
  local config_file="$1"
  local group="$2"
  local key="$3"

  awk -F'=' -v group="${group}" -v key="${key}" '
    BEGIN { in_group = 0; found = 0 }
    /^[[:space:]]*\[/ {
      line = $0
      sub(/^[[:space:]]*\[/, "", line)
      sub(/\][[:space:]]*$/, "", line)
      in_group = (line == group)
      next
    }
    in_group {
      lhs = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
      if (lhs == key) {
        found = 1
        exit
      }
    }
    END { exit found ? 0 : 1 }
  ' "${config_file}"
}

get_aur_helper() {
  local helper=""

  if command -v yay >/dev/null 2>&1; then
    helper="yay"
  elif command -v paru >/dev/null 2>&1; then
    helper="paru"
  fi

  aur_helper="${helper}"
  [[ -n "${helper}" ]] || return 1
  printf '%s\n' "${helper}"
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
  if [ -t 1 ]; then return 0; fi
  local ignore_paste_file="$HYPR_STATE_HOME/ignore.paste"

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

  local ignore_class="${*#*--ignore=}"
  [[ "$*" != *--ignore=* ]] && ignore_class=""
  if [ -n "${ignore_class}" ]; then
    echo "${ignore_class}" >>"${ignore_paste_file}"
    print_log -y "[ignore]" "'$ignore_class'"
    return 0
  fi
  local class
  class=$(hyprctl -j activewindow | jq -r '.initialClass')
  if ! grep -q "${class}" "${ignore_paste_file}"; then
    if command -v wtype >/dev/null; then
      hyprctl -q dispatch exec 'wtype -M ctrl V -m ctrl'
    elif command -v hyprctl >/dev/null; then
      hyprctl -q dispatch sendshortcut CTRL,V,activewindow
    fi
  fi
}

#? Checks if the cursor is hovered on a window
is_hovered() {
  local data=""
  local -a hovered_values=()
  local cursor_x=0 cursor_y=0 window_x=0 window_y=0 window_size_x=0 window_size_y=0

  data=$(hyprctl --batch -j "cursorpos;activewindow" | jq -s '.[0] * .[1]') || return 1
  readarray -t hovered_values < <(
    printf '%s\n' "${data}" | jq -r '
      (.x // 0),
      (.y // 0),
      (.at[0] // 0),
      (.at[1] // 0),
      (.size[0] // 0),
      (.size[1] // 0)
    '
  )
  ((${#hovered_values[@]} == 6)) || return 1

  cursor_x="${hovered_values[0]}"
  cursor_y="${hovered_values[1]}"
  window_x="${hovered_values[2]}"
  window_y="${hovered_values[3]}"
  window_size_x="${hovered_values[4]}"
  window_size_y="${hovered_values[5]}"
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
    local group_esc kv
    group_esc="$(escape_regex "${group}")"
    kv="$(sed_escape_append_text "${key}=${value}")"

    if ! grep -q "^\[${group_esc}\]" "${config_file}"; then
      echo -e "\n[${group}]\n${key}=${value}" >>"${config_file}"
    elif ! ini_group_has_key "${config_file}" "${group}" "${key}"; then
      sed -i "/^\[${group_esc}\]/a ${kv}" "${config_file}"
    fi
  fi
}
