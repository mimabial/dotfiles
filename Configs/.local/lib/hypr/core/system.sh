#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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
  hyprshell pm query "${pkgIn}" &>/dev/null
}

escape_regex() {
  printf '%s' "$1" | sed 's/[][(){}.^$?*+|\\/]/\\&/g'
}

sed_escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "${value}"
}

get_aur_helper() {
  local helper=""

  if command -v yay >/dev/null 2>&1; then
    helper="yay"
  elif command -v paru >/dev/null 2>&1; then
    helper="paru"
  fi

  [[ -n "${helper}" ]] || return 1
  printf '%s\n' "${helper}"
}

get_hypr_conf_from_file() {
  local file="$1"
  local key="$2"

  [[ -r "${file}" ]] || return 1

  awk -F'=' -v key="${key}" '
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
  ' "${file}"
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

  value="$(get_hypr_conf_from_file "${file}" "\$${hyVar}")"
  if [[ -n "${value}" ]] && [[ "${value}" != \$* ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  defaults_file="$(hypr_variables_file)"
  if [[ -f "${defaults_file}" ]]; then
    get_hypr_conf_from_file "${defaults_file}" "\$default.${hyVar}"
  fi
}

#? handle pasting
paste_string() {
  local class=""
  local arg=""
  local ignored_class=""
  local -a ignored_classes=(
    kitty
    org.kde.konsole
    terminator
    XTerm
    Alacritty
    xterm-256color
  )

  if [ -t 1 ]; then return 0; fi

  for arg in "$@"; do
    case "${arg}" in
      --ignore=*)
        ignored_class="${arg#--ignore=}"
        [[ -n "${ignored_class}" ]] && ignored_classes+=("${ignored_class}")
        ;;
    esac
  done

  class=$(hyprctl -j activewindow | jq -r '.initialClass // empty')
  for ignored_class in "${ignored_classes[@]}"; do
    [[ "${class}" == "${ignored_class}" ]] && return 0
  done

  if command -v wtype >/dev/null; then
    hyprctl -q dispatch exec 'wtype -M ctrl V -m ctrl'
  elif command -v hyprctl >/dev/null; then
    hyprctl -q dispatch sendshortcut CTRL,V,activewindow
  fi
}

# ============================================================================
# ini_write - Write a key=value pair to an INI/KConfig file
# ============================================================================
# Arguments:
#   $1 - Config file path
#   $2 - Group/section name (e.g., "General", "Colors:View")
#   $3 - Key name
#   $4 - Value to write
# Returns:
#   0 - Value written or updated
#   1 - Invalid input or write failure
# Notes:
#   - Uses kwriteconfig6 if available, falls back to a bounded awk rewrite
#   - Creates group section if it doesn't exist
# Example:
#   ini_write "${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals" "Icons" "Theme" "Papirus"
ini_write() {
  local config_file="${1}"
  local group="${2}"
  local key="${3}"
  local value="${4}"

  # Validate inputs
  [[ -z "${config_file}" ]] && return 1
  [[ -z "${group}" ]] && return 1
  [[ -z "${key}" ]] && return 1

  if [[ ! -f "${config_file}" ]]; then
    mkdir -p "$(dirname "${config_file}")" || return 1
    : >"${config_file}" || return 1
  fi

  if command -v kwriteconfig6 >/dev/null 2>&1 &&
    kwriteconfig6 --file "${config_file}" --group "${group}" --key "${key}" "${value}" 2>/dev/null; then
    return 0
  fi

  local tmp_file=""
  tmp_file="$(mktemp "$(dirname "${config_file}")/.ini-write.XXXXXX")" || return 1

  awk -v group="${group}" -v key="${key}" -v value="${value}" '
    BEGIN {
      in_group = 0
      group_found = 0
      key_written = 0
    }
    /^[[:space:]]*\[/ {
      if (in_group && !key_written) {
        print key "=" value
        key_written = 1
      }

      section = $0
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\][[:space:]]*$/, "", section)
      in_group = (section == group)
      if (in_group) {
        group_found = 1
      }

      print
      next
    }
    {
      if (in_group) {
        split($0, parts, "=")
        lhs = parts[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
        if (lhs == key) {
          if (!key_written) {
            print key "=" value
            key_written = 1
          }
          next
        }
      }

      print
    }
    END {
      if (in_group && !key_written) {
        print key "=" value
        key_written = 1
      }

      if (!group_found) {
        if (NR > 0) {
          print ""
        }
        print "[" group "]"
        print key "=" value
      }
    }
  ' "${config_file}" >"${tmp_file}" || {
    rm -f "${tmp_file}"
    return 1
  }

  mv -f "${tmp_file}" "${config_file}" || {
    rm -f "${tmp_file}"
    return 1
  }
}
