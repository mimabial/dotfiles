#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# color.apply.sh - Apply generated colors to applications
#
# OVERVIEW:
#   Orchestrates the application of pywal16-generated colors to various
#   applications (GTK, Qt, terminals, waybar, etc.). File-generating theming
#   scripts run inline so color.set.sh only returns after outputs exist.
#
# USAGE:
#   source color.apply.sh
#   run_app_theming
#   run_secondary_theming
#
# DEPENDENCIES:
#   - LIB_DIR must be set (path to ~/.local/lib)
#   - print_log function from globalcontrol.sh
#   - ini_write function from globalcontrol.sh (for post_updates)
#
# GLOBAL VARIABLES:
#   ASYNC_OPTIONAL_UPDATES - If 1, optional external updates may run async

# Primary and secondary theming scripts are defined here so color.set.sh does
# not need to shadow the same orchestration logic.
declare -a APP_THEMING_SCRIPTS=(
  "wal/wal.kvantum.sh"
  "wal/wal.gtk.sh"
)

declare -a SECONDARY_THEMING_SCRIPTS=(
  "wal/wal.chrome.sh"
  "wal/wal.qt.sh"
  "wal/wal.gimp.sh"
  "theme/dconf.set.sh"
)

# Run theming scripts inline. These scripts materialize config/state files and
# must complete before the theme apply path returns.
run_theming_scripts() {
  local -n scripts_ref="$1"
  local script script_path

  for script in "${scripts_ref[@]}"; do
    script_path="${LIB_DIR}/hypr/${script}"
    [[ ! -f "${script_path}" ]] && continue
    bash "${script_path}"
  done
}

# Run primary app theming scripts.
run_app_theming() {
  run_theming_scripts APP_THEMING_SCRIPTS
}

# Run secondary app theming scripts.
run_secondary_theming() {
  run_theming_scripts SECONDARY_THEMING_SCRIPTS
}

# Send reload signals to running applications.
reload_live_apps() {
  pkill -SIGUSR1 kitty 2>/dev/null || true

  local tmux_config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
    tmux source-file "${tmux_config}" 2>/dev/null || true
  fi

  local rmpc_config="${XDG_CONFIG_HOME:-$HOME/.config}/rmpc/config.ron"
  local rmpc_theme_name=""
  local rmpc_theme_path=""
  if command -v rmpc &>/dev/null && pgrep -x rmpc >/dev/null 2>&1 && [[ -f "${rmpc_config}" ]]; then
    rmpc_theme_name="$(grep -oP 'theme:\s*Some\("\K[^"]+' "${rmpc_config}" 2>/dev/null | head -1)"
    if [[ -n "${rmpc_theme_name}" ]]; then
      rmpc_theme_path="${XDG_CONFIG_HOME:-$HOME/.config}/rmpc/themes/${rmpc_theme_name}.ron"
      [[ -f "${rmpc_theme_path}" ]] && rmpc remote set theme "${rmpc_theme_path}" >/dev/null 2>&1 || true
    fi
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
    ini_write "${target_file}" "${section}" "${key}" "${value}"
  done
}

kde_theme_palette() {
  bg="${background}"
  fg="${foreground}"
  accent="${color4}"
  hover="${color5}"

  if [ "${selected_color_mode}" -eq 0 ]; then
    local theme_kvconfig="${HYPR_THEME_DIR}/kvantum/kvconfig.theme"
    if [ -f "${theme_kvconfig}" ]; then
      local kv_colors kv_bg kv_fg kv_hl
      kv_colors=$(awk -F= '
        /^window\.color=/ {bg=$2}
        /^text\.color=/   {fg=$2}
        /^highlight\.color=/ {hl=$2}
        END {print bg"|"fg"|"hl}
      ' "${theme_kvconfig}")
      kv_bg="${kv_colors%%|*}"
      kv_colors="${kv_colors#*|}"
      kv_fg="${kv_colors%%|*}"
      kv_hl="${kv_colors#*|}"
      [[ -n "${kv_bg}" ]] && bg="${kv_bg}"
      [[ -n "${kv_fg}" ]] && fg="${kv_fg}"
      [[ -n "${kv_hl}" ]] && accent="${kv_hl}" && hover="${kv_hl}"
    fi
  fi

  bg=$(normalize_hex_color "${bg}")
  fg=$(normalize_hex_color "${fg}")
  accent=$(normalize_hex_color "${accent}")
  hover=$(normalize_hex_color "${hover}")

  bg_rgb=$(hex_to_rgb "${bg}")
  fg_rgb=$(hex_to_rgb "${fg}")
  accent_rgb=$(hex_to_rgb "${accent}")
  hover_rgb=$(hex_to_rgb "${hover}")
}

ensure_kde_scheme_file() {
  mkdir -p "${kde_scheme_dir}"
  if [[ -f "${kde_scheme_file}" ]]; then
    return 0
  fi

  if [[ -f "/usr/share/color-schemes/Kvantum.colors" ]]; then
    cp -f "/usr/share/color-schemes/Kvantum.colors" "${kde_scheme_file}"
  elif [[ -f "/usr/share/color-schemes/BreezeDark.colors" ]]; then
    cp -f "/usr/share/color-schemes/BreezeDark.colors" "${kde_scheme_file}"
  fi
}

write_kde_scheme_identity() {
  if [[ -f "${kde_scheme_file}" ]]; then
    kde_write_entries "${kde_scheme_file}" \
      $'General\tName\t'"${kde_scheme_name}" \
      $'General\tColorScheme\t'"${kde_scheme_name}"
  fi
  kde_write_entries "${kdeglobals}" $'UiSettings\tColorScheme\t'"${kde_scheme_name}"
}

write_kde_scheme_palette() {
  [[ -f "${kde_scheme_file}" ]] || return 0
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
}

write_kdeglobals_palette() {
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
}

reload_hypr_shaders() {
  local reload_output=""

  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] || return 0
  if ! reload_output="$(hyprshell shaders --reload 2>&1)"; then
    print_log -sec "hyprshell" -warn "reload" "shader reload failed"
    return 1
  fi

  if grep -qi "error" <<<"${reload_output}"; then
    print_log -sec "hyprshell" -warn "reload" "shader reload reported errors"
    return 1
  fi

  [[ "${LOG_LEVEL}" == "debug" ]] && print_log -sec "hyprshell" -stat "reload" "shaders"
  return 0
}

post_updates() {
  if [ -n "${background}" ] && [ -n "${foreground}" ]; then
    local hash_file prev_hash scheme_missing color_hash
    kdeglobals="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
    kde_scheme_name="${KDE_COLOR_SCHEME:-colors}"
    kde_scheme_dir="${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes"
    kde_scheme_file="${kde_scheme_dir}/${kde_scheme_name}.colors"

    kde_theme_palette
    hash_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/kdeglobals.hash"
    prev_hash=""
    scheme_missing=0
    color_hash="${bg_rgb}|${fg_rgb}|${accent_rgb}|${ICON_THEME:-}|${kde_scheme_name}"
    [[ -f "${hash_file}" ]] && prev_hash=$(cat "${hash_file}" 2>/dev/null)
    [[ ! -f "${kde_scheme_file}" ]] && scheme_missing=1

    ensure_kde_scheme_file
    write_kde_scheme_identity

    if [[ "${color_hash}" != "${prev_hash}" || "${scheme_missing}" -eq 1 ]]; then
      write_kde_scheme_palette
      write_kdeglobals_palette
      echo "${color_hash}" >"${hash_file}"
    fi
  fi

  reload_hypr_shaders
}
