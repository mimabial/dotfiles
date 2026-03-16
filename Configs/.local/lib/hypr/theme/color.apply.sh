#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# color.apply.sh - Apply generated colors to applications
#
# OVERVIEW:
#   Orchestrates the application of pywal16-generated colors to various
#   applications (GTK, Qt, terminals, waybar, etc.). Runs theming scripts
#   in parallel for performance with proper PID tracking.
#
# USAGE:
#   source color.apply.sh
#   run_app_theming
#   wait_for_theming_jobs_when_async_disabled
#   run_secondary_theming
#   wait_for_theming_jobs_when_async_disabled
#
# DEPENDENCIES:
#   - LIB_DIR must be set (path to ~/.local/lib)
#   - print_log function from globalcontrol.sh
#   - toml_write function from globalcontrol.sh (for post_updates)
#
# GLOBAL VARIABLES:
#   APP_THEMING_PIDS - Array of background job PIDs (managed by this module)
#   ASYNC_APPS       - If 1, don't wait for background jobs

# Track background job PIDs for proper synchronization
declare -a APP_THEMING_PIDS=()

# Primary and secondary theming scripts are defined here so color.set.sh does
# not need to shadow the same orchestration logic.
declare -a APP_THEMING_SCRIPTS=(
  "wal/wal.kvantum.sh"
  "wal/wal.gtk.sh"
  "wal/wal.tmux.sh"
  "wal/wal.qutebrowser.sh"
)

declare -a SECONDARY_THEMING_SCRIPTS=(
  "wal/wal.chrome.sh"
  "wal/wal.qt.sh"
  "theme/dconf.set.sh"
)

# ============================================================================
# wait_with_timeout - Wait for background jobs with timeout protection
# ============================================================================
# Arguments:
#   $1 - Timeout in seconds (default: 30)
#   $@ - PIDs to wait for (after first argument)
# Returns:
#   0 - All processes completed or were killed
# Notes:
#   - Kills stalled processes after timeout
#   - Prevents infinite hangs from misbehaving scripts
wait_with_timeout() {
  local timeout="${1:-30}"
  local pids=("${@:2}")

  # Validate inputs
  [[ ${#pids[@]} -eq 0 ]] && return 0
  [[ ! "${timeout}" =~ ^[0-9]+$ ]] && timeout=30

  local start_time elapsed
  start_time=$(date +%s)

  for pid in "${pids[@]}"; do
    # Skip invalid PIDs
    [[ ! "${pid}" =~ ^[0-9]+$ ]] && continue

    # Check if process is still running
    if kill -0 "${pid}" 2>/dev/null; then
      elapsed=$(( $(date +%s) - start_time ))
      local remaining=$(( timeout - elapsed ))
      if [[ ${remaining} -le 0 ]]; then
        type print_log &>/dev/null && print_log -sec "pywal16" -warn "timeout" "killing stalled job ${pid}"
        kill -TERM "${pid}" 2>/dev/null
        continue
      fi
      # Wait for this specific PID with remaining timeout
      timeout "${remaining}" tail --pid="${pid}" -f /dev/null 2>/dev/null || true
    fi
  done
}

# ============================================================================
# wait_for_theming_jobs_when_async_disabled - Wait for background theming jobs only in sync mode
# ============================================================================
# Arguments: none
# Global variables:
#   ASYNC_APPS       - If 1, skip waiting
#   APP_THEMING_PIDS - Array of PIDs to wait for
# Returns:
#   0 - Always succeeds
# Notes:
#   - Clears APP_THEMING_PIDS array after waiting
#   - Uses 30s timeout to prevent hangs
wait_for_theming_jobs_when_async_disabled() {
  if [[ "${ASYNC_APPS:-0}" -eq 1 ]]; then
    return 0
  fi
  wait_with_timeout 30 "${APP_THEMING_PIDS[@]}"
  APP_THEMING_PIDS=()
}

# ============================================================================
# run_app_theming - Run primary app theming scripts in parallel
# ============================================================================
# Arguments: none
# Global variables:
#   LIB_DIR          - Path to library directory
#   APP_THEMING_PIDS - Array to store spawned PIDs
# Returns:
#   0 - Scripts spawned successfully
# Notes:
#   - Scripts are run in background for parallelism
#   - Use wait_for_theming_jobs_when_async_disabled() to synchronize after calling
run_app_theming() {
  APP_THEMING_PIDS=()

  local script_path
  for script in "${APP_THEMING_SCRIPTS[@]}"; do
    script_path="${LIB_DIR}/hypr/${script}"
    if [[ -f "${script_path}" ]]; then
      bash "${script_path}" &
      APP_THEMING_PIDS+=($!)
    fi
  done

  # Special case: pywalfox (external command, not a script)
  if command -v pywalfox &>/dev/null; then
    {
      pywalfox update &>/dev/null &&
        type print_log &>/dev/null &&
        print_log -sec "pywalfox" -stat "updated" "Firefox theme"
    } &
    APP_THEMING_PIDS+=($!)
  fi
}

# ============================================================================
# run_secondary_theming - Run secondary app theming scripts
# ============================================================================
# Arguments: none
# Global variables:
#   LIB_DIR          - Path to library directory
#   APP_THEMING_PIDS - Array to store spawned PIDs (cleared first)
# Returns:
#   0 - Scripts spawned successfully
# Notes:
#   - These scripts may depend on ICON_THEME being set
#   - Run after primary theming and icon theme extraction
run_secondary_theming() {
  APP_THEMING_PIDS=()

  local script_path
  for script in "${SECONDARY_THEMING_SCRIPTS[@]}"; do
    script_path="${LIB_DIR}/hypr/${script}"
    if [[ -f "${script_path}" ]]; then
      bash "${script_path}" &
      APP_THEMING_PIDS+=($!)
    fi
  done
}

# ============================================================================
# reload_live_apps - Send reload signals to running applications
# ============================================================================
# Arguments: none
# Returns:
#   0 - Signals sent (apps may or may not be running)
# Notes:
#   - Kitty: SIGUSR1 for color reload
#   - Tmux: source-file for config reload
reload_live_apps() {
  pkill -SIGUSR1 kitty 2>/dev/null || true

  local tmux_config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
    tmux source-file "${tmux_config}" 2>/dev/null || true
  fi
}

# ============================================================================
# hex_to_rgb - Convert hex color to RGB format
# ============================================================================
# Arguments:
#   $1 - Hex color (with or without # prefix)
# Output:
#   Prints "R,G,B" to stdout
# Example:
#   rgb=$(hex_to_rgb "#ff5500")  # Output: "255,85,0"
hex_to_rgb() {
  local hex="${1#\#}"

  # Validate input
  [[ ! "${hex}" =~ ^[0-9A-Fa-f]{6}$ ]] && {
    echo "0,0,0"
    return 1
  }

  printf "%d,%d,%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# ============================================================================
# post_updates - Update KDE/Dolphin settings with current colors
# ============================================================================
# Arguments: none
# Global variables:
#   background, foreground, color4, color5 - Pywal colors
#   selected_color_mode  - Color mode (0=theme, 1+=wallpaper)
#   HYPR_THEME_DIR  - Path to current theme directory
#   ICON_THEME      - Current icon theme name
#   TERMINAL        - Terminal emulator command
# Returns:
#   0 - Updates applied or skipped (colors unchanged)
# Notes:
#   - Writes to ~/.config/kdeglobals
#   - Uses hash-check to skip redundant writes
#   - In theme mode, reads colors from Kvantum config
post_updates() {
  if [ -n "${background}" ] && [ -n "${foreground}" ]; then
    local kdeglobals="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
    local kde_scheme_name="${KDE_COLOR_SCHEME:-colors}"
    local kde_scheme_dir="${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes"
    local kde_scheme_file="${kde_scheme_dir}/${kde_scheme_name}.colors"
    local bg="${background}"
    local fg="${foreground}"
    local accent="${color4}"
    local hover="${color5}"

    if [ "${selected_color_mode}" -eq 0 ]; then
      local theme_kvconfig="${HYPR_THEME_DIR}/kvantum/kvconfig.theme"
      if [ -f "${theme_kvconfig}" ]; then
        local kv_colors
        kv_colors=$(awk -F= '
          /^window\.color=/ {bg=$2}
          /^text\.color=/   {fg=$2}
          /^highlight\.color=/ {hl=$2}
          END {print bg"|"fg"|"hl}
        ' "${theme_kvconfig}")
        local kv_bg="${kv_colors%%|*}"
        kv_colors="${kv_colors#*|}"
        local kv_fg="${kv_colors%%|*}"
        local kv_hl="${kv_colors#*|}"
        [[ -n "${kv_bg}" ]] && bg="${kv_bg}"
        [[ -n "${kv_fg}" ]] && fg="${kv_fg}"
        [[ -n "${kv_hl}" ]] && accent="${kv_hl}" && hover="${kv_hl}"
      fi
    fi

    local bg_rgb fg_rgb accent_rgb hover_rgb
    bg_rgb=$(hex_to_rgb "${bg}")
    fg_rgb=$(hex_to_rgb "${fg}")
    accent_rgb=$(hex_to_rgb "${accent}")
    hover_rgb=$(hex_to_rgb "${hover}")

    local color_hash="${bg_rgb}|${fg_rgb}|${accent_rgb}|${ICON_THEME:-}|${kde_scheme_name}"
    local hash_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/kdeglobals.hash"
    local prev_hash=""
    local scheme_missing=0
    [[ -f "${hash_file}" ]] && prev_hash=$(cat "${hash_file}" 2>/dev/null)
    [[ ! -f "${kde_scheme_file}" ]] && scheme_missing=1

    mkdir -p "${kde_scheme_dir}"
    if [[ ! -f "${kde_scheme_file}" ]]; then
      if [[ -f "/usr/share/color-schemes/Kvantum.colors" ]]; then
        cp -f "/usr/share/color-schemes/Kvantum.colors" "${kde_scheme_file}"
      elif [[ -f "/usr/share/color-schemes/BreezeDark.colors" ]]; then
        cp -f "/usr/share/color-schemes/BreezeDark.colors" "${kde_scheme_file}"
      fi
    fi

    if [[ -f "${kde_scheme_file}" ]]; then
      toml_write "${kde_scheme_file}" "General" "Name" "${kde_scheme_name}"
      toml_write "${kde_scheme_file}" "General" "ColorScheme" "${kde_scheme_name}"
      toml_write "${kdeglobals}" "UiSettings" "ColorScheme" "${kde_scheme_name}"
    fi

    if [[ "${color_hash}" != "${prev_hash}" || "${scheme_missing}" -eq 1 ]]; then
      if [[ -f "${kde_scheme_file}" ]]; then
        toml_write "${kde_scheme_file}" "Colors:View" "BackgroundNormal" "${bg_rgb}"
        toml_write "${kde_scheme_file}" "Colors:View" "ForegroundNormal" "${fg_rgb}"
        toml_write "${kde_scheme_file}" "Colors:View" "DecorationFocus" "${accent_rgb}"
        toml_write "${kde_scheme_file}" "Colors:View" "DecorationHover" "${hover_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Selection" "BackgroundNormal" "${accent_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Selection" "BackgroundAlternate" "${accent_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Selection" "ForegroundNormal" "${fg_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Selection" "ForegroundActive" "${fg_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Selection" "DecorationFocus" "${accent_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Selection" "DecorationHover" "${hover_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Window" "BackgroundNormal" "${bg_rgb}"
        toml_write "${kde_scheme_file}" "Colors:Window" "ForegroundNormal" "${fg_rgb}"
      fi

      [[ -n "${ICON_THEME}" ]] && toml_write "${kdeglobals}" "Icons" "Theme" "${ICON_THEME}"
      [[ -n "${TERMINAL}" ]] && toml_write "${kdeglobals}" "General" "TerminalApplication" "${TERMINAL}"
      toml_write "${kdeglobals}" "Colors:View" "BackgroundNormal" "${bg_rgb}"
      toml_write "${kdeglobals}" "Colors:View" "ForegroundNormal" "${fg_rgb}"
      toml_write "${kdeglobals}" "Colors:View" "DecorationFocus" "${accent_rgb}"
      toml_write "${kdeglobals}" "Colors:View" "DecorationHover" "${hover_rgb}"
      toml_write "${kdeglobals}" "Colors:Button" "BackgroundNormal" "${bg_rgb}"
      toml_write "${kdeglobals}" "Colors:Button" "BackgroundAlternate" "${bg_rgb}"
      toml_write "${kdeglobals}" "Colors:Button" "ForegroundNormal" "${fg_rgb}"
      toml_write "${kdeglobals}" "Colors:Button" "DecorationFocus" "${accent_rgb}"
      toml_write "${kdeglobals}" "Colors:Button" "DecorationHover" "${hover_rgb}"
      toml_write "${kdeglobals}" "Colors:Selection" "BackgroundNormal" "${accent_rgb}"
      toml_write "${kdeglobals}" "Colors:Selection" "BackgroundAlternate" "${accent_rgb}"
      toml_write "${kdeglobals}" "Colors:Selection" "ForegroundNormal" "${fg_rgb}"
      toml_write "${kdeglobals}" "Colors:Selection" "ForegroundActive" "${fg_rgb}"
      toml_write "${kdeglobals}" "Colors:Selection" "DecorationFocus" "${accent_rgb}"
      toml_write "${kdeglobals}" "Colors:Selection" "DecorationHover" "${hover_rgb}"
      toml_write "${kdeglobals}" "Colors:Window" "BackgroundNormal" "${bg_rgb}"
      toml_write "${kdeglobals}" "Colors:Window" "ForegroundNormal" "${fg_rgb}"
      toml_write "${kdeglobals}" "Colors:Header" "BackgroundNormal" "${bg_rgb}"
      toml_write "${kdeglobals}" "Colors:Header" "ForegroundNormal" "${fg_rgb}"
      toml_write "${kdeglobals}" "Colors:Header" "DecorationFocus" "${accent_rgb}"
      toml_write "${kdeglobals}" "Colors:Header" "DecorationHover" "${hover_rgb}"
      toml_write "${kdeglobals}" "Colors:Tooltip" "BackgroundNormal" "${bg_rgb}"
      toml_write "${kdeglobals}" "Colors:Tooltip" "ForegroundNormal" "${fg_rgb}"
      toml_write "${kdeglobals}" "Colors:Complementary" "BackgroundNormal" "${bg_rgb}"
      toml_write "${kdeglobals}" "Colors:Complementary" "ForegroundNormal" "${fg_rgb}"
      echo "${color_hash}" >"${hash_file}"
    fi
  fi

  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && {
    if ! hyprshell shaders --reload 2>&1 | grep -q "error"; then
      [[ "${LOG_LEVEL}" == "debug" ]] && print_log -sec "hyprshell" -stat "reload" "shaders"
    else
      print_log -sec "hyprshell" -warn "reload" "shader reload failed"
    fi
  }
}
