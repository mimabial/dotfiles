#!/usr/bin/env bash
# shellcheck disable=SC1091
# shellcheck disable=SC1090
#
# globalcontrol.sh - Core utilities for HyDE shell scripts
#
# This file provides common functions and environment setup for all HyDE scripts.
# Source this file at the start of any script that needs access to theme settings,
# wallpaper management, or system configuration.
#
# Key exports:
#   HYPR_CONFIG_HOME, HYPR_DATA_HOME, HYPR_CACHE_HOME, HYPR_STATE_HOME
#   LIB_DIR, scrDir, confDir
#
# Key functions:
#   print_log()        - Colored logging output
#   get_hashmap()      - Find wallpapers with hashes for caching
#   get_themes()       - Populate theme list arrays
#   export_hypr_config() - Load state variables from staterc/config
#   get_hyprConf()     - Get value from theme's hypr.theme file
#   set_conf()         - Update a variable in staterc
#   pkg_installed()    - Check if a package is installed
#   state_get/set()    - Unified state management API

# xdg resolution
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# hypr envs
export HYPR_CONFIG_HOME="${XDG_CONFIG_HOME}/hypr"
export HYPR_DATA_HOME="${XDG_DATA_HOME}/hypr"
export HYPR_CACHE_HOME="${XDG_CACHE_HOME}/hypr"
export HYPR_STATE_HOME="${XDG_STATE_HOME}/hypr"
export HYPR_RUNTIME_DIR="${XDG_RUNTIME_DIR}/hypr"
export ICONS_DIR="${XDG_DATA_HOME}/icons"
export FONTS_DIR="${XDG_DATA_HOME}/fonts"
export THEMES_DIR="${XDG_DATA_HOME}/themes"

#legacy hypr envs // should be deprecated

export SHARE_DIR="${XDG_DATA_HOME}"
export scrDir="${LIB_DIR:-$HOME/.local/lib}/hypr"
export confDir="${XDG_CONFIG_HOME:-$HOME/.config}"
export hyprConfDir="$HYPR_CONFIG_HOME"
export cacheDir="$HYPR_CACHE_HOME"
export WALLPAPER_CACHE_DIR="${HYPR_CACHE_HOME}/wallpaper"
export WALLPAPER_CURRENT_DIR="${WALLPAPER_CACHE_DIR}/current"
export WALLPAPER_THUMB_DIR="${WALLPAPER_CACHE_DIR}/thumbs"
export WALLPAPER_VIDEO_DIR="${WALLPAPER_CURRENT_DIR}/thumbnails"
export thmbDir="$WALLPAPER_THUMB_DIR"
export iconsDir="$ICONS_DIR"
export themesDir="$THEMES_DIR"
export fontsDir="$FONTS_DIR"
# Use xxh64sum for faster hashing (3x faster than sha1sum)
export hashMech="xxh64sum"

#? avoid notify-send to stall the script
send_notifs() {
  local args=("$@")
  notify-send "${args[@]}" &
}

print_log() {
  # [ -t 1 ] && return 0 # Skip if not in the terminal
  while (("$#")); do
    # [ "${colored}" == "true" ]
    case "$1" in
      -r | +r)
        echo -ne "\e[31m$2\e[0m" >&2
        shift 2
        ;; # Red
      -g | +g)
        echo -ne "\e[32m$2\e[0m" >&2
        shift 2
        ;; # Green
      -y | +y)
        echo -ne "\e[33m$2\e[0m" >&2
        shift 2
        ;; # Yellow
      -b | +b)
        echo -ne "\e[34m$2\e[0m" >&2
        shift 2
        ;; # Blue
      -m | +m)
        echo -ne "\e[35m$2\e[0m" >&2
        shift 2
        ;; # Magentass
      -c | +c)
        echo -ne "\e[36m$2\e[0m" >&2
        shift 2
        ;; # Cyan
      -wt | +w)
        echo -ne "\e[37m$2\e[0m" >&2
        shift 2
        ;; # White
      -n | +n)
        echo -ne "\e[96m$2\e[0m" >&2
        shift 2
        ;; # Neon
      -stat)
        echo -ne "\e[4;30;46m $2 \e[0m :: " >&2
        shift 2
        ;; # status
      -crit)
        echo -ne "\e[30;41m $2 \e[0m :: " >&2
        shift 2
        ;; # critical
      -warn)
        echo -ne "WARNING :: \e[30;43m $2 \e[0m :: " >&2
        shift 2
        ;; # warning
      +)
        echo -ne "\e[38;5;$2m$3\e[0m" >&2
        shift 3
        ;; # Set color manually
      -sec)
        echo -ne "\e[32m[$2] \e[0m" >&2
        shift 2
        ;; # section use for logs
      -err)
        echo -ne "ERROR :: \e[4;31m$2 \e[0m" >&2
        shift 2
        ;; #error
      *)
        echo -ne "$1" >&2
        shift
        ;;
    esac
  done
  echo "" >&2
}

get_hashmap() {
  unset wallHash
  unset wallList
  unset skipStrays
  unset filetypes

  # Initialize supported file extensions (safe: no eval needed)
  local -a supported_files=(
    "gif"
    "jpg"
    "jpeg"
    "png"
    "${WALLPAPER_FILETYPES[@]}"
  )
  if [ -n "${WALLPAPER_OVERRIDE_FILETYPES}" ]; then
    supported_files=("${WALLPAPER_OVERRIDE_FILETYPES[@]}")
  fi

  find_wallpapers() {
    local wallSource="$1"

    if [ -z "${wallSource}" ]; then
      print_log -err "ERROR: wallSource is empty"
      return 1
    fi

    # Build find arguments safely using arrays (no eval needed)
    local -a find_args=(-H "${wallSource}" -type f \()
    local first_ext=true

    # Add file extension patterns
    for ext in "${supported_files[@]}"; do
      if [[ "${first_ext}" == true ]]; then
        find_args+=(-iname "*.${ext}")
        first_ext=false
      else
        find_args+=(-o -iname "*.${ext}")
      fi
    done
    find_args+=(\) ! -path "*/logo/*" -exec "${hashMech}" {} +)

    [ "${LOG_LEVEL}" == "debug" ] && print_log -g "DEBUG:" -b "Running find with args:" "${find_args[*]}"

    local tmpfile error_output
    tmpfile=$(mktemp)
    # Execute find directly with array expansion (safe: no eval, proper quoting)
    find "${find_args[@]}" 2>"$tmpfile" | sort -k2
    error_output=$(<"$tmpfile") && rm -f "$tmpfile"
    [ -n "${error_output}" ] && print_log -err "ERROR:" -b "found an error: " -r "${error_output}" -y " skipping..."

  }

  for wallSource in "$@"; do

    [ "${LOG_LEVEL}" == "debug" ] && print_log -g "DEBUG:" -b "wallpaper source path:" "${wallSource}"

    [ -z "${wallSource}" ] && continue
    [ "${wallSource}" == "--no-notify" ] && no_notify=1 && continue
    [ "${wallSource}" == "--skipstrays" ] && skipStrays=1 && continue
    [ "${wallSource}" == "--verbose" ] && verboseMap=1 && continue

    wallSource="$(realpath "${wallSource}")"

    [ -e "${wallSource}" ] || {
      print_log -err "ERROR:" -b "wallpaper source does not exist:" "${wallSource}" -y " skipping..."
      continue
    }

    [ "${LOG_LEVEL}" == "debug" ] && print_log -g "DEBUG:" -b "wallSource path:" "${wallSource}"

    hashMap=$(find_wallpapers "${wallSource}") # Enable debug mode for testing

    # hashMap=$(
    # find "${wallSource}" -type f \( -iname "*.gif" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.mkv"  \) ! -path "*/logo/*" -exec "${hashMech}" {} + | sort -k2
    # )

    if [ -z "${hashMap}" ]; then
      no_wallpapers+=("${wallSource}")
      print_log -warn "No compatible wallpapers found in: " "${wallSource}"
      continue
    fi

    while read -r hash image; do
      wallHash+=("${hash}")
      wallList+=("${image}")
    done <<<"${hashMap}"
  done

  # Notify the list of directories without compatible wallpapers
  if [ "${#no_wallpapers[@]}" -gt 0 ]; then
    print_log -warn "No compatible wallpapers found in:" "${no_wallpapers[*]}"
  fi

  if [ -z "${#wallList[@]}" ] || [[ "${#wallList[@]}" -eq 0 ]]; then
    if [[ "${skipStrays}" -eq 1 ]]; then
      return 1
    else
      echo "ERROR: No image found in any source"
      [ -n "${no_notify}" ] && notify-send -a "Global control" "WARNING: No compatible wallpapers found in: ${no_wallpapers[*]}"
      exit 1
    fi
  fi

  if [[ "${verboseMap}" -eq 1 ]]; then
    echo "// Hash Map //"
    for indx in "${!wallHash[@]}"; do
      echo ":: \${wallHash[${indx}]}=\"${wallHash[indx]}\" :: \${wallList[${indx}]}=\"${wallList[indx]}\""
    done
  fi
}

# ============================================================================
# get_themes - Populate theme list arrays from themes directory
# ============================================================================
# Arguments: none
# Global variables set:
#   thmList[] - Array of theme names
#   thmWall[] - Array of wallpaper paths (corresponding to thmList)
#   thmSort[] - Array of sort order values
# Returns:
#   0 - Always succeeds
# Notes:
#   - Reads from $HYPR_CONFIG_HOME/themes/
#   - Sorts themes by .sort file value
#   - Fixes broken wall.set symlinks automatically
# Example:
#   get_themes
#   for i in "${!thmList[@]}"; do
#     echo "Theme: ${thmList[$i]}, Wallpaper: ${thmWall[$i]}"
#   done
# shellcheck disable=SC2120
get_themes() {
  unset thmSortS
  unset thmListS
  unset thmWallS
  unset thmSort
  unset thmList
  unset thmWall

  while read -r thmDir; do
    local realWallPath
    realWallPath="$(readlink "${thmDir}/wall.set")"
    if [ ! -e "${realWallPath}" ]; then
      get_hashmap "${thmDir}" --skipstrays || continue
      echo "fixing link :: ${thmDir}/wall.set"
      ln -fs "${wallList[0]}" "${thmDir}/wall.set"
    fi
    [ -f "${thmDir}/.sort" ] && thmSortS+=("$(head -1 "${thmDir}/.sort")") || thmSortS+=("0")
    thmWallS+=("${realWallPath}")
    thmListS+=("${thmDir##*/}") # Use this instead of basename
  done < <(find -H "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d)

  while IFS='|' read -r sort theme wall; do
    thmSort+=("${sort}")
    thmList+=("${theme}")
    thmWall+=("${wall}")
  done < <(paste -d '|' <(printf "%s\n" "${thmSortS[@]}") <(printf "%s\n" "${thmListS[@]}") <(printf "%s\n" "${thmWallS[@]}") | sort -n -k 1 -k 2)
  #!  done < <(parallel --link echo "{1}\|{2}\|{3}" ::: "${thmSortS[@]}" ::: "${thmListS[@]}" ::: "${thmWallS[@]}" | sort -n -k 1 -k 2) # This is overkill and slow
  if [ "${1}" == "--verbose" ]; then
    echo "// Theme Control //"
    for indx in "${!thmList[@]}"; do
      echo -e ":: \${thmSort[${indx}]}=\"${thmSort[indx]}\" :: \${thmList[${indx}]}=\"${thmList[indx]}\" :: \${thmWall[${indx}]}=\"${thmWall[indx]}\""
    done
  fi
}

export_hypr_config() {
  #? This function is used to re-source config files if
  #? 1. they change since the script was started
  #? 2. the script is run in a new shell instance
  #? This function is used to re-source config files in the following scenarios:
  #? 1. If the config files change since the script was started (e.g., another process or user updates theme or state).
  #?    Example: You edit your theme or state config while this script is running; call export_hypr_config to reload changes.
  #? 2. If the script is run in a new shell instance (e.g., after opening a new terminal or sourcing this script in a subshell).
  #?    Example: You start a new shell session and want to ensure the latest config is loaded; call export_hypr_config at the start.
  #? 3. If you need arrays from the config to be available in the current shell session (since bash does not export arrays).
  #?    Example: You want to use theme or wall arrays in your shell; call export_hypr_config to populate them.
  #?
  #? Usage: Call export_hypr_config whenever you need to ensure the current shell has up-to-date config and arrays.
  #? Typically called after config changes, at shell startup, or before using config-dependent arrays.

  local user_conf_state="${XDG_STATE_HOME}/hypr/staterc"
  local user_conf="${XDG_STATE_HOME}/hypr/config"

  [ -f "${user_conf_state}" ] && source "${user_conf_state}"
  [ -f "${user_conf}" ] && source "${user_conf}"
}

# ============================================================================
# GLOBAL INITIALIZATION
# ============================================================================
# This section handles initialization that happens when the script is sourced.
# Use HYPR_SKIP_INIT=1 to skip auto-initialization (for scripts that need
# to control when state is loaded).
#
# To reload state after changes: call export_hypr_config explicitly
# To force full re-init: unset HYPR_GLOBAL_INIT and source again
# ============================================================================

# Initialize hypr environment (loads state, sets defaults)
# Called automatically unless HYPR_SKIP_INIT=1
init_hypr_globals() {
  # Guard against re-initialization (unless reload_flag is set)
  if [[ "${HYPR_GLOBAL_INIT:-0}" -eq 1 ]] && [[ "${reload_flag:-0}" -ne 1 ]]; then
    return 0
  fi

  # Load user state
  export_hypr_config

  # Validate color mode
  case "${enableWallDcol}" in
    0 | 1 | 2 | 3) ;;
    *) enableWallDcol=0 ;;
  esac

  # Set theme if not already set
  if [ -z "${HYPR_THEME}" ] || [ ! -d "${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}" ]; then
    get_themes
    HYPR_THEME="${thmList[0]}"
  fi

  # Derived paths
  HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"

  # Export theme variables
  export HYPR_THEME \
    HYPR_THEME_DIR \
    enableWallDcol

  # Hyprland-specific settings (only if running under Hyprland)
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]; then
    hypr_border="$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq '.int' 2>/dev/null)"
    hypr_width="$(hyprctl -j getoption general:border_size 2>/dev/null | jq '.int' 2>/dev/null)"
  fi
  export hypr_border=${hypr_border:-${HYPR_BORDER_RADIUS:-2}}
  export hypr_width=${hypr_width:-${HYPR_BORDER_WIDTH:-2}}

  # Mark as initialized
  HYPR_GLOBAL_INIT=1
}

# Auto-initialize unless explicitly skipped
if [[ "${HYPR_SKIP_INIT:-0}" -ne 1 ]]; then
  init_hypr_globals
fi

#// extra fns

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

get_aurhlpr() {
  if pkg_installed yay; then
    aurhlpr="yay"
  elif pkg_installed paru; then
    # shellcheck disable=SC2034
    aurhlpr="paru"
  fi
}

# ============================================================================
# UNIFIED STATE MANAGEMENT
# ============================================================================
# All state is stored in key=value format in these files:
#   - staterc: User/runtime state (HYPR_THEME, enableWallDcol, etc.)
#   - config:  Exported environment config
#   - mode:    Current color mode (dark/light)
#
# Use these functions for consistent state access across all scripts:
#   state_get  - Read a state variable
#   state_set  - Write a state variable (atomic)
#   state_file - Get path to a state file
# ============================================================================

# State file paths (centralized definition)
[[ -z "${STATE_DIR}" ]] && STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
readonly STATE_DIR
[[ -z "${STATE_RC}" ]] && STATE_RC="${STATE_DIR}/staterc"
readonly STATE_RC
[[ -z "${STATE_CONFIG}" ]] && STATE_CONFIG="${STATE_DIR}/config"
readonly STATE_CONFIG
[[ -z "${STATE_MODE}" ]] && STATE_MODE="${STATE_DIR}/mode"
readonly STATE_MODE

# Get a state variable value
# Usage: state_get VARIABLE_NAME [default_value]
# Checks: staterc, config, then returns default
state_get() {
  local var_name="$1"
  local default_value="${2:-}"
  local value=""

  # Validate input
  if [[ -z "${var_name}" ]]; then
    echo "${default_value}"
    return 1
  fi

  # Check staterc first (primary state file)
  if [[ -f "${STATE_RC}" ]]; then
    value=$(grep "^${var_name}=" "${STATE_RC}" 2>/dev/null | tail -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
  fi

  # Fall back to config if not found
  if [[ -z "${value}" ]] && [[ -f "${STATE_CONFIG}" ]]; then
    value=$(grep "^${var_name}=" "${STATE_CONFIG}" 2>/dev/null | tail -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
  fi

  # Return value or default
  echo "${value:-${default_value}}"
}

# Set a state variable (atomic write to prevent race conditions)
# Usage: state_set VARIABLE_NAME value [file]
# file: "staterc" (default), "config", or "mode"
state_set() {
  local var_name="$1"
  local var_value="$2"
  local target_file="${3:-staterc}"
  local state_file

  # Determine target file
  case "${target_file}" in
    staterc) state_file="${STATE_RC}" ;;
    config)  state_file="${STATE_CONFIG}" ;;
    mode)    state_file="${STATE_MODE}" ;;
    *)       state_file="${STATE_RC}" ;;
  esac

  if [[ -z "${state_file}" ]]; then
    case "${target_file}" in
      staterc) state_file="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc" ;;
      config)  state_file="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/config" ;;
      mode)    state_file="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/mode" ;;
    esac
  fi

  if [[ -z "${state_file}" ]]; then
    print_log -sec "state" -err "state_set" "state file not set"
    return 1
  fi

  # Ensure directory exists
  mkdir -p "$(dirname "${state_file}")"

  # Lock state updates to avoid concurrent writers clobbering each other.
  local lock_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
  local lock_file="${lock_dir}/state-${target_file}.lock"
  local lock_timeout="${STATE_LOCK_TIMEOUT:-5}"
  local lock_fd

  mkdir -p "${lock_dir}"
  if ! exec {lock_fd}>"${lock_file}"; then
    print_log -sec "state" -err "state_set" "failed to open lock ${lock_file}"
    return 1
  fi
  if ! flock -w "${lock_timeout}" "${lock_fd}"; then
    print_log -sec "state" -warn "state_set" "lock busy (${lock_file})"
    exec {lock_fd}>&-
    return 1
  fi

  # Special case for mode file (single value, no key)
  if [[ "${target_file}" == "mode" ]]; then
    if [[ -z "${var_value}" ]]; then
      print_log -sec "state" -err "state_set" "mode value required"
      flock -u "${lock_fd}" 2>/dev/null || true
      exec {lock_fd}>&-
      return 1
    fi
    printf "%s\n" "${var_value}" > "${state_file}.tmp" && mv -f "${state_file}.tmp" "${state_file}"
    local rc=$?
    flock -u "${lock_fd}" 2>/dev/null || true
    exec {lock_fd}>&-
    return "${rc}"
  fi

  # Validate input
  if [[ -z "${var_name}" ]]; then
    print_log -sec "state" -err "state_set" "variable name required"
    flock -u "${lock_fd}" 2>/dev/null || true
    exec {lock_fd}>&-
    return 1
  fi

  # Atomic update using temp file
  local tmp_file="${state_file}.tmp.$$"
  touch "${state_file}"
  local var_escaped
  var_escaped="$(printf "%s" "${var_name}" | sed 's/[][\\.^$*+?()|{}]/\\&/g')"

  # Remove old value and add new one atomically
  {
    grep -v "^${var_escaped}=" "${state_file}" 2>/dev/null || true
    echo "${var_name}=\"${var_value}\""
  } > "${tmp_file}"

  # Atomic move
  if mv -f "${tmp_file}" "${state_file}"; then
    flock -u "${lock_fd}" 2>/dev/null || true
    exec {lock_fd}>&-
    return 0
  else
    rm -f "${tmp_file}" 2>/dev/null
    print_log -sec "state" -err "state_set" "failed to write ${var_name}"
    flock -u "${lock_fd}" 2>/dev/null || true
    exec {lock_fd}>&-
    return 1
  fi
}

# Get the current color mode
# Returns: dark, light, or empty
state_get_mode() {
  if [[ -f "${STATE_MODE}" ]]; then
    cat "${STATE_MODE}" 2>/dev/null
  else
    echo "dark"  # Default
  fi
}

# Set the current color mode
# Usage: state_set_mode dark|light
state_set_mode() {
  local mode="$1"
  if [[ ! "${mode}" =~ ^(dark|light)$ ]]; then
    print_log -sec "state" -err "state_set_mode" "invalid mode '${mode}' (expected dark|light)"
    return 1
  fi
  state_set "" "${mode}" "mode"
}

# ============================================================================
# set_conf - Set a state variable (legacy wrapper)
# ============================================================================
# Arguments:
#   $1 - Variable name
#   $2 - Variable value
# Returns:
#   0 - Success
#   1 - Failure
# Notes:
#   Legacy function - prefer state_set() for new code
set_conf() {
  local varName="${1}"
  local varData="${2}"
  state_set "${varName}" "${varData}" "staterc"
}

# ============================================================================
# set_hash - Generate hash for an image file
# ============================================================================
# Arguments:
#   $1 - Path to image file
# Output:
#   Prints hash string to stdout
# Returns:
#   0 - Success
#   1 - Invalid input or file not readable
# Example:
#   hash=$(set_hash "/path/to/wallpaper.png")
set_hash() {
  local hashImage="${1}"

  # Validate input
  if [[ -z "${hashImage}" ]]; then
    return 1
  fi
  if [[ ! -r "${hashImage}" ]]; then
    return 1
  fi

  "${hashMech}" "${hashImage}" | awk '{print $1}'
}

check_package() {

  local lock_file="${XDG_RUNTIME_DIR:-/tmp}/hypr/__package.lock"
  mkdir -p "${XDG_RUNTIME_DIR:-/tmp}/hypr"

  if [ -f "$lock_file" ]; then
    return 0
  fi

  for pkg in "$@"; do
    if ! pkg_installed "${pkg}"; then
      print_log -err "Package is not installed" "'${pkg}'"
      rm -f "$lock_file"
      exit 1
    fi
  done

  touch "$lock_file"
}

# ============================================================================
# get_hyprConf - Get a variable value from Hyprland theme config
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
#   gtk_theme=$(get_hyprConf "GTK_THEME")
get_hyprConf() {
  local hyVar="${1}"
  local file="${2:-"$HYPR_THEME_DIR/hypr.theme"}"

  # Validate input
  if [[ -z "${hyVar}" ]]; then
    return 1
  fi

  # Validate file exists
  if [[ ! -r "${file}" ]]; then
    return 1
  fi

  # First try using hyq for fast config parsing if available
  if command -v hyq &>/dev/null; then
    local hyq_result
    # Try with source option for accurate results
    hyq_result=$(hyq -s --query "\$${hyVar}" "${file}" 2>/dev/null)
    # If empty, try without source option
    if [ -z "${hyq_result}" ]; then
      hyq_result=$(hyq --query "\$${hyVar}" "${file}" 2>/dev/null)
    fi
    # Return result if not empty
    [ -n "${hyq_result}" ] && echo "${hyq_result}" && return 0

  fi

  # Fall back to traditional parsing if hyq fails or isn't available
  local gsVal
  gsVal="$(grep "^[[:space:]]*\$${hyVar}\s*=" "${file}" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "${gsVal}" ] && [[ "${gsVal}" != \$* ]] && echo "${gsVal}" && return 0
  declare -A gsMap=(
    [GTK_THEME]="gtk-theme"
    [ICON_THEME]="icon-theme"
    [COLOR_SCHEME]="color-scheme"
    [CURSOR_THEME]="cursor-theme"
    [CURSOR_SIZE]="cursor-size"
    [FONT]="font-name"
    [DOCUMENT_FONT]="document-font-name"
    [MONOSPACE_FONT]="monospace-font-name"
    [FONT_SIZE]="font-size"
    [DOCUMENT_FONT_SIZE]="document-font-size"
    [MONOSPACE_FONT_SIZE]="monospace-font-size"
    # [CODE_THEME]="Wallbash"
    # [SDDM_THEME]=""
  )

  # Try parse gsettings
  if [[ -n "${gsMap[$hyVar]}" ]]; then
    gsVal="$(awk -F"[\"']" '/^[[:space:]]*exec[[:space:]]*=[[:space:]]*gsettings[[:space:]]*set[[:space:]]*org.gnome.desktop.interface[[:space:]]*'"${gsMap[$hyVar]}"'[[:space:]]*/ {last=$2} END {print last}' "${file}")"
  fi

  if [ -z "${gsVal}" ] || [[ "${gsVal}" == \$* ]]; then
    case "${hyVar}" in
      "CODE_THEME") echo "Wallbash" ;;
      "SDDM_THEME") echo "" ;;
      *)
        grep "^[[:space:]]*\$default.${hyVar}\s*=" \
          "$HYPR_CONFIG_HOME/variables.conf" |
          cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -n 1
        ;;
    esac
  else
    echo "${gsVal}"
  fi

}

# launcher spawn location (wofi/rofi)
get_rofi_pos() {
  local window_width="${1:-0}"  # Window width in pixels (optional)
  local window_height="${2:-0}" # Window height in pixels (optional)

  # Auto-calculate clipboard theme dimensions if no size provided
  if [ "$window_width" -eq 0 ] && [ "$window_height" -eq 0 ]; then
    # Wofi doesn't have -dump-theme, use fallback defaults
    local font_scale="${ROFI_SCALE:-10}"
    window_width=$((23 * font_scale * 2))
    window_height=$((30 * font_scale * 2))
  fi

  readarray -t curPos < <(hyprctl cursorpos -j | jq -r '.x,.y')
  eval "$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) |
        "monRes=(\(.width) \(.height) \(.scale) \(.x) \(.y)) offRes=(\(.reserved | join(" ")))"')"

  monRes[2]="${monRes[2]//./}"
  monRes[0]=$((monRes[0] * 100 / monRes[2]))
  monRes[1]=$((monRes[1] * 100 / monRes[2]))
  curPos[0]=$((curPos[0] - monRes[3]))
  curPos[1]=$((curPos[1] - monRes[4]))
  offRes=("${offRes// / }")

  # Calculate available space and determine anchor
  local edge_padding=10  # Minimum distance from screen edges
  local available_right=$((monRes[0] - curPos[0] - offRes[2]))
  local available_left=$((curPos[0] - offRes[0]))
  local available_bottom=$((monRes[1] - curPos[1] - offRes[3]))
  local available_top=$((curPos[1] - offRes[1]))

  # Calculate max safe offset to prevent window from going off screen
  # Add extra padding to account for window size estimation errors
  local max_safe_right=$((monRes[0] - window_width - offRes[2] - edge_padding))
  local max_safe_bottom=$((monRes[1] - window_height - offRes[3] - edge_padding))

  # X positioning with overflow prevention
  if [ "$window_width" -gt 0 ]; then
    if [ "$available_right" -ge "$window_width" ]; then
      # Enough space on the right - stick to cursor
      local x_pos="west"
      local x_off="$((curPos[0] - offRes[0]))"
      # Clamp to prevent overflow
      [ "$x_off" -gt "$max_safe_right" ] && x_off="$max_safe_right"
    elif [ "$available_left" -ge "$window_width" ]; then
      # Enough space on the left - stick to cursor
      local x_pos="east"
      local x_off="-$((monRes[0] - curPos[0] - offRes[2]))"
      # Clamp to prevent overflow (negative direction)
      local abs_x_off=$((monRes[0] - curPos[0] - offRes[2]))
      [ "$abs_x_off" -gt "$max_safe_right" ] && x_off="-$max_safe_right"
    else
      # Not enough space either side, use the side with more space
      if [ "$available_right" -ge "$available_left" ]; then
        local x_pos="west"
        local x_off="$edge_padding"  # Stick to left edge with padding
      else
        local x_pos="east"
        local x_off="-$((monRes[0] - window_width - offRes[2] - edge_padding))"  # Stick to right edge with padding
      fi
    fi
  else
    # Fallback to quadrant-based positioning
    if [ "${curPos[0]}" -ge "$((monRes[0] / 2))" ]; then
      local x_pos="east"
      local x_off="-$((monRes[0] - curPos[0] - offRes[2]))"
    else
      local x_pos="west"
      local x_off="$((curPos[0] - offRes[0]))"
    fi
  fi

  # Y positioning with overflow prevention
  if [ "$window_height" -gt 0 ]; then
    if [ "$available_bottom" -ge "$window_height" ]; then
      # Enough space below - stick to cursor
      local y_pos="north"
      local y_off="$((curPos[1] - offRes[1]))"
      # Clamp to prevent overflow
      [ "$y_off" -gt "$max_safe_bottom" ] && y_off="$max_safe_bottom"
    elif [ "$available_top" -ge "$window_height" ]; then
      # Enough space above - stick to cursor
      local y_pos="south"
      local y_off="-$((monRes[1] - curPos[1] - offRes[3]))"
      # Clamp to prevent overflow (negative direction)
      local abs_y_off=$((monRes[1] - curPos[1] - offRes[3]))
      [ "$abs_y_off" -gt "$max_safe_bottom" ] && y_off="-$max_safe_bottom"
    else
      # Not enough space either direction, use the side with more space
      if [ "$available_bottom" -ge "$available_top" ]; then
        local y_pos="north"
        local y_off="$edge_padding"  # Stick to top edge with padding
      else
        local y_pos="south"
        local y_off="-$((monRes[1] - window_height - offRes[3] - edge_padding))"  # Stick to bottom edge with padding
      fi
    fi
  else
    # Fallback to quadrant-based positioning
    if [ "${curPos[1]}" -ge "$((monRes[1] / 2))" ]; then
      local y_pos="south"
      local y_off="-$((monRes[1] - curPos[1] - offRes[3]))"
    else
      local y_pos="north"
      local y_off="$((curPos[1] - offRes[1]))"
    fi
  fi

  local coordinates="window{location:${x_pos} ${y_pos};anchor:${x_pos} ${y_pos};x-offset:${x_off}px;y-offset:${y_off}px;}"
  echo "${coordinates}"
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

  ignore_class=$(echo "$@" | awk -F'--ignore=' '{print $2}')
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
  eval "$(echo "$data" | jq -r '@sh "cursor_x=\(.x) cursor_y=\(.y) window_x=\(.at[0]) window_y=\(.at[1]) window_size_x=\(.size[0]) window_size_y=\(.size[1])"')"

  # Handle variables in case they are null
  cursor_x=${cursor_x:-$(jq -r '.x // 0' <<<"$data")}
  cursor_y=${cursor_y:-$(jq -r '.y // 0' <<<"$data")}
  window_x=${window_x:-$(jq -r '.at[0] // 0' <<<"$data")}
  window_y=${window_y:-$(jq -r '.at[1] // 0' <<<"$data")}
  window_size_x=${window_size_x:-$(jq -r '.size[0] // 0' <<<"$data")}
  window_size_y=${window_size_y:-$(jq -r '.size[1] // 0' <<<"$data")}
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

# ============================================================================
# extract_thumbnail - Extract a thumbnail frame from a video file
# ============================================================================
# Arguments:
#   $1 - Path to video file
#   $2 - Output path for thumbnail image
# Returns:
#   0 - Success
#   1 - Failed to extract thumbnail
# Notes:
#   - Uses ffmpeg to extract frame
#   - Extracts 5th frame by default
# shellcheck disable=SC2317
extract_thumbnail() {
  local x_wall="${1}"
  x_wall=$(realpath "${x_wall}")
  local temp_image="${2}"
  ffmpeg -y -i "${x_wall}" -vf "thumbnail,scale=1000:-1" -frames:v 1 -update 1 "${temp_image}" &>/dev/null
}

# Function to check if the file is supported by the wallpaper backend
accepted_mime_types() {
  local mime_types_array=${1}
  local file=${2}

  for mime_type in "${mime_types_array[@]}"; do
    if file --mime-type -b "${file}" | grep -q "^${mime_type}"; then
      return 0
    else
      print_log -err "File type not supported for this wallpaper backend."
      notify-send -u critical -a "Global control" "File type not supported for this wallpaper backend."
    fi

  done

}

dconf_write() {
  local key="$1"
  local value="$2"
  if dconf write "${key}" "'${value}'"; then
    print_log -sec "dconf" -stat "set" "${key} to ${value}"
  else
    print_log -sec "dconf" -warn "failed to set" "${key}"
  fi
}

hyprlogout() {
  if command -v hyprctl >/dev/null 2>&1; then
    if hyprctl dispatch exit; then
      return 0
    fi
  fi

  if command -v loginctl >/dev/null 2>&1; then
    if [[ -n "${XDG_SESSION_ID:-}" ]] && loginctl terminate-session "${XDG_SESSION_ID}"; then
      return 0
    fi
    if [[ -n "${USER:-}" ]] && loginctl terminate-user "${USER}"; then
      return 0
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user exit
    return $?
  fi

  print_log -err "ERROR: No supported logout method found"
  return 1
}

if [ -n "$BASH_VERSION" ]; then
  export -f get_hyprConf get_rofi_pos \
    is_hovered toml_write \
    get_hashmap get_aurhlpr \
    set_conf set_hash check_package \
    get_themes print_log \
    pkg_installed paste_string \
    extract_thumbnail accepted_mime_types \
    dconf_write send_notifs \
    hyprlogout \
    export_hypr_config init_hypr_globals \
    state_get state_set state_get_mode state_set_mode
fi
