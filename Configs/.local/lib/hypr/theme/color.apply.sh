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
)

declare -a SECONDARY_THEMING_SCRIPTS=(
  "wal/wal.chrome.sh"
  "wal/wal.qt.sh"
  "theme/dconf.set.sh"
)

# Run a theming script group either inline or in the background.
run_theming_scripts() {
  local -n scripts_ref="$1"
  local script script_path

  for script in "${scripts_ref[@]}"; do
    script_path="${LIB_DIR}/hypr/${script}"
    [[ ! -f "${script_path}" ]] && continue

    if [[ "${ASYNC_APPS:-0}" -eq 1 ]]; then
      bash "${script_path}" &
      APP_THEMING_PIDS+=("$!")
    else
      bash "${script_path}"
    fi
  done
}

# Clear async PID state when theming ran inline.
wait_for_theming_jobs_when_async_disabled() {
  if [[ "${ASYNC_APPS:-0}" -eq 1 ]]; then
    return 0
  fi
  APP_THEMING_PIDS=()
}

# Run primary app theming scripts.
run_app_theming() {
  APP_THEMING_PIDS=()
  run_theming_scripts APP_THEMING_SCRIPTS

  # Special case: pywalfox (external command, not a script)
  if command -v pywalfox &>/dev/null; then
    if [[ "${ASYNC_APPS:-0}" -eq 1 ]]; then
      {
        pywalfox update &>/dev/null &&
          type print_log &>/dev/null &&
          print_log -sec "pywalfox" -stat "updated" "Firefox theme"
      } &
      APP_THEMING_PIDS+=($!)
    else
      pywalfox update &>/dev/null &&
        type print_log &>/dev/null &&
        print_log -sec "pywalfox" -stat "updated" "Firefox theme"
    fi
  fi
}

# Run secondary app theming scripts.
run_secondary_theming() {
  APP_THEMING_PIDS=()
  run_theming_scripts SECONDARY_THEMING_SCRIPTS
}

# Send reload signals to running applications.
reload_live_apps() {
  pkill -SIGUSR1 kitty 2>/dev/null || true

  local tmux_config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
    tmux source-file "${tmux_config}" 2>/dev/null || true
  fi
}

# Convert #RRGGBB to R,G,B.
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
# normalize_hex_color - Strip inline comments/whitespace from a hex color
# ============================================================================
# Arguments:
#   $1 - Raw color value (e.g. "#2C2525 ; comment")
# Output:
#   Prints normalized "#RRGGBB" if recoverable, else the original trimmed value
normalize_hex_color() {
  local raw="${1%%;*}"
  local stripped=""
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"

  if [[ "${raw}" =~ ^#?[0-9A-Fa-f]{8}$ ]]; then
    stripped="${raw#\#}"
    printf '#%s' "${stripped:0:6}"
    return 0
  fi

  if [[ "${raw}" =~ ^#?[0-9A-Fa-f]{6}$ ]]; then
    printf '#%s' "${raw#\#}"
    return 0
  fi

  printf '%s' "${raw}"
}

# Batch-write TOML key/value entries encoded as section<TAB>key<TAB>value.
kde_write_entries() {
  local target_file="$1"
  shift

  local entry section key value
  for entry in "$@"; do
    IFS=$'\t' read -r section key value <<< "${entry}"
    toml_write "${target_file}" "${section}" "${key}" "${value}"
  done
}

# Update KDE/Dolphin settings with the current palette.
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

    bg=$(normalize_hex_color "${bg}")
    fg=$(normalize_hex_color "${fg}")
    accent=$(normalize_hex_color "${accent}")
    hover=$(normalize_hex_color "${hover}")

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
      kde_write_entries "${kde_scheme_file}" \
        $'General\tName\t'"${kde_scheme_name}" \
        $'General\tColorScheme\t'"${kde_scheme_name}"
      kde_write_entries "${kdeglobals}" \
        $'UiSettings\tColorScheme\t'"${kde_scheme_name}"
    fi

    if [[ "${color_hash}" != "${prev_hash}" || "${scheme_missing}" -eq 1 ]]; then
      if [[ -f "${kde_scheme_file}" ]]; then
        kde_write_entries "${kde_scheme_file}" \
          $'Colors:View\tBackgroundNormal\t'"${bg_rgb}" \
          $'Colors:View\tForegroundNormal\t'"${fg_rgb}" \
          $'Colors:View\tDecorationFocus\t'"${accent_rgb}" \
          $'Colors:View\tDecorationHover\t'"${hover_rgb}" \
          $'Colors:Selection\tBackgroundNormal\t'"${accent_rgb}" \
          $'Colors:Selection\tBackgroundAlternate\t'"${accent_rgb}" \
          $'Colors:Selection\tForegroundNormal\t'"${fg_rgb}" \
          $'Colors:Selection\tForegroundActive\t'"${fg_rgb}" \
          $'Colors:Selection\tDecorationFocus\t'"${accent_rgb}" \
          $'Colors:Selection\tDecorationHover\t'"${hover_rgb}" \
          $'Colors:Window\tBackgroundNormal\t'"${bg_rgb}" \
          $'Colors:Window\tForegroundNormal\t'"${fg_rgb}"
      fi

      local -a kdeglobals_entries=(
        $'Colors:View\tBackgroundNormal\t'"${bg_rgb}"
        $'Colors:View\tForegroundNormal\t'"${fg_rgb}"
        $'Colors:View\tDecorationFocus\t'"${accent_rgb}"
        $'Colors:View\tDecorationHover\t'"${hover_rgb}"
        $'Colors:Button\tBackgroundNormal\t'"${bg_rgb}"
        $'Colors:Button\tBackgroundAlternate\t'"${bg_rgb}"
        $'Colors:Button\tForegroundNormal\t'"${fg_rgb}"
        $'Colors:Button\tDecorationFocus\t'"${accent_rgb}"
        $'Colors:Button\tDecorationHover\t'"${hover_rgb}"
        $'Colors:Selection\tBackgroundNormal\t'"${accent_rgb}"
        $'Colors:Selection\tBackgroundAlternate\t'"${accent_rgb}"
        $'Colors:Selection\tForegroundNormal\t'"${fg_rgb}"
        $'Colors:Selection\tForegroundActive\t'"${fg_rgb}"
        $'Colors:Selection\tDecorationFocus\t'"${accent_rgb}"
        $'Colors:Selection\tDecorationHover\t'"${hover_rgb}"
        $'Colors:Window\tBackgroundNormal\t'"${bg_rgb}"
        $'Colors:Window\tForegroundNormal\t'"${fg_rgb}"
        $'Colors:Header\tBackgroundNormal\t'"${bg_rgb}"
        $'Colors:Header\tForegroundNormal\t'"${fg_rgb}"
        $'Colors:Header\tDecorationFocus\t'"${accent_rgb}"
        $'Colors:Header\tDecorationHover\t'"${hover_rgb}"
        $'Colors:Tooltip\tBackgroundNormal\t'"${bg_rgb}"
        $'Colors:Tooltip\tForegroundNormal\t'"${fg_rgb}"
        $'Colors:Complementary\tBackgroundNormal\t'"${bg_rgb}"
        $'Colors:Complementary\tForegroundNormal\t'"${fg_rgb}"
      )
      [[ -n "${ICON_THEME}" ]] && kdeglobals_entries+=($'Icons\tTheme\t'"${ICON_THEME}")
      [[ -n "${TERMINAL}" ]] && kdeglobals_entries+=($'General\tTerminalApplication\t'"${TERMINAL}")
      kde_write_entries "${kdeglobals}" "${kdeglobals_entries[@]}"
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
