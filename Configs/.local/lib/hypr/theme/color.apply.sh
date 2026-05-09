#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# Subsystem inputs:
#   selected_color_mode      - set by color-sync.sh via color.plan.sh
#   background, foreground   - pywal palette, sourced by color.finalize.sh
#   color4, color5           - pywal palette accent slots
: "${selected_color_mode-}" "${background-}" "${foreground-}" "${color4-}" "${color5-}"
#
# color.apply.sh - Apply generated colors to applications
#
# OVERVIEW:
#   Orchestrates the application of pywal16-generated colors to various
#   applications (GTK, Qt, terminals, waybar, etc.). File-generating theming
#   scripts run inline so color-sync.sh only returns after outputs exist.
#
# USAGE:
#   source color.apply.sh
#   write_primary_app_theme_outputs
#   write_secondary_app_theme_outputs
#
# DEPENDENCIES:
#   - LIB_DIR must be set (path to ~/.local/lib)
#   - print_log function from core/notify.sh
#   - ini_write function from core/system.sh (for post_updates)

# Primary and secondary theming scripts are defined here so color-sync.sh does
# not need to shadow the same orchestration logic.
declare -ga APP_THEMING_SCRIPTS=(
  "wal/wal.kvantum.sh"
)

declare -ga SECONDARY_THEMING_SCRIPTS=()

# Run theming scripts inline. These scripts write config/state files and must
# complete before the theme apply path returns. Pass the script paths as
# positional args so the array is expanded at the call site.
write_theme_outputs_from_scripts() {
  local script script_path
  local start_ms="" end_ms="" script_rc=0
  local rc=0

  for script in "$@"; do
    script_path="${LIB_DIR}/hypr/${script}"
    [[ ! -f "${script_path}" ]] && continue
    start_ms="$(date +%s%3N)"
    bash "${script_path}"
    script_rc=$?
    end_ms="$(date +%s%3N)"
    if [[ "${HYPR_THEME_TIMING:-0}" == "1" || "${LOG_LEVEL:-}" == "debug" ]]; then
      print_log -sec "color-sync" -stat "timing" "script:${script}: $((end_ms - start_ms))ms rc=${script_rc}"
    fi
    if [[ "${script_rc}" -ne 0 ]]; then
      print_log -sec "theme" -err "apply" "failed ${script}"
      rc=1
    fi
  done

  return "${rc}"
}

# Write primary app theme files and derived state.
write_primary_app_theme_outputs() {
  if [[ "${HYPR_THEME_DEFER_QT_OUTPUTS:-0}" -eq 1 ]]; then
    return 0
  fi

  write_theme_outputs_from_scripts "${APP_THEMING_SCRIPTS[@]}"
}

runtime_desktop_sync_is_external() {
  [[ "${HYPR_THEME_RUNTIME_SYNC_EXTERNAL:-0}" -eq 1 ]]
}

live_theme_reload_is_deferred() {
  [[ "${HYPR_THEME_BATCH_RELOADS:-0}" -eq 1 ]]
}

run_runtime_desktop_sync() {
  local desktop_sync_script="${LIB_DIR}/hypr/theme/desktop.sync.sh"
  [[ -x "${desktop_sync_script}" ]] || return 0
  bash "${desktop_sync_script}" --runtime-only
}

# Write secondary app theme files and derived state.
write_secondary_app_theme_outputs() {
  write_theme_outputs_from_scripts "${SECONDARY_THEMING_SCRIPTS[@]}"
  runtime_desktop_sync_is_external || run_runtime_desktop_sync
}

# Signal or live-reload running applications so they pick up fresh theme files.
reload_live_theme_client() {
  local client="$1"
  local tmux_config=""
  local rmpc_config=""
  local rmpc_theme_name=""
  local rmpc_theme_path=""

  case "${client}" in
    kitty)
      pkill -SIGUSR1 -x kitty 2>/dev/null || true
      ;;
    tmux)
      tmux_config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
      if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
        tmux source-file "${tmux_config}" 2>/dev/null || true
      fi
      ;;
    rmpc)
      rmpc_config="${XDG_CONFIG_HOME:-$HOME/.config}/rmpc/config.ron"
      if ! command -v rmpc &>/dev/null || ! pgrep -x rmpc >/dev/null 2>&1 || [[ ! -f "${rmpc_config}" ]]; then
        return 0
      fi

      rmpc_theme_name="$(grep -oP 'theme:\s*Some\("\K[^"]+' "${rmpc_config}" 2>/dev/null | head -1)"
      case "${rmpc_theme_name}" in
        pywal16 | pywal16-small | pywal16-big) ;;
        *) return 0 ;;
      esac

      rmpc_theme_path="${XDG_CONFIG_HOME:-$HOME/.config}/rmpc/themes/${rmpc_theme_name}.ron"
      [[ -f "${rmpc_theme_path}" ]] && rmpc remote set theme "${rmpc_theme_path}" >/dev/null 2>&1 || true
      ;;
  esac
}

signal_and_reload_live_apps() {
  local -a clients=("$@")
  local client=""
  live_theme_reload_is_deferred && return 0
  [[ ${#clients[@]} -gt 0 ]] || clients=(kitty tmux rmpc)

  for client in "${clients[@]}"; do
    reload_live_theme_client "${client}"
  done
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
  selection_fg="${foreground}"
  inactive_selection_fg=""

  if [ "${selected_color_mode}" -eq 0 ]; then
    local theme_kvconfig="${HYPR_THEME_DIR}/kvantum/kvconfig.theme"
    if [ -f "${theme_kvconfig}" ]; then
      local kv_bg="" kv_fg="" kv_hl="" kv_hl_fg=""
      kv_colors=$(awk -F= '
        /^window\.color=/ {bg=$2}
        /^text\.color=/   {fg=$2}
        /^highlight\.color=/ {hl=$2}
        /^highlight\.text\.color=/ {hlfg=$2}
        END {print bg"|"fg"|"hl"|"hlfg}
      ' "${theme_kvconfig}")
      IFS='|' read -r kv_bg kv_fg kv_hl kv_hl_fg <<< "${kv_colors}"
      [[ -n "${kv_bg}" ]] && bg="${kv_bg}"
      [[ -n "${kv_fg}" ]] && fg="${kv_fg}"
      [[ -n "${kv_hl}" ]] && accent="${kv_hl}" && hover="${kv_hl}"
      [[ -n "${kv_hl_fg}" ]] && selection_fg="${kv_hl_fg}"
    fi
  fi

  [[ -n "${inactive_selection_fg}" ]] || inactive_selection_fg="${selection_fg}"

  bg=$(normalize_hex_color "${bg}")
  fg=$(normalize_hex_color "${fg}")
  accent=$(normalize_hex_color "${accent}")
  hover=$(normalize_hex_color "${hover}")
  selection_fg=$(normalize_hex_color "${selection_fg}")
  inactive_selection_fg=$(normalize_hex_color "${inactive_selection_fg}")

  bg_rgb=$(hex_to_rgb "${bg}")
  fg_rgb=$(hex_to_rgb "${fg}")
  accent_rgb=$(hex_to_rgb "${accent}")
  hover_rgb=$(hex_to_rgb "${hover}")
  selection_fg_rgb=$(hex_to_rgb "${selection_fg}")
  inactive_selection_fg_rgb=$(hex_to_rgb "${inactive_selection_fg}")
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
	  $'Colors:Button\tBackgroundNormal\t'"${bg_rgb}" \
	  $'Colors:Button\tBackgroundAlternate\t'"${bg_rgb}" \
	  $'Colors:Button\tForegroundNormal\t'"${fg_rgb}" \
	  $'Colors:Button\tDecorationFocus\t'"${accent_rgb}" \
	  $'Colors:Button\tDecorationHover\t'"${hover_rgb}" \
	  $'Colors:View\tBackgroundAlternate\t'"${bg_rgb}" \
	  $'Colors:View\tBackgroundNormal\t'"${bg_rgb}" \
	  $'Colors:View\tForegroundNormal\t'"${fg_rgb}" \
	  $'Colors:View\tDecorationFocus\t'"${accent_rgb}" \
	  $'Colors:View\tDecorationHover\t'"${hover_rgb}" \
    $'Colors:Selection\tBackgroundNormal\t'"${accent_rgb}" \
    $'Colors:Selection\tBackgroundAlternate\t'"${accent_rgb}" \
    $'Colors:Selection\tForegroundNormal\t'"${selection_fg_rgb}" \
    $'Colors:Selection\tForegroundActive\t'"${selection_fg_rgb}" \
    $'Colors:Selection\tForegroundInactive\t'"${inactive_selection_fg_rgb}" \
    $'Colors:Selection\tDecorationFocus\t'"${accent_rgb}" \
    $'Colors:Selection\tDecorationHover\t'"${hover_rgb}" \
	  $'Colors:Window\tBackgroundAlternate\t'"${bg_rgb}" \
	  $'Colors:Window\tBackgroundNormal\t'"${bg_rgb}" \
	  $'Colors:Window\tForegroundNormal\t'"${fg_rgb}" \
	  $'Colors:Header\tBackgroundAlternate\t'"${bg_rgb}" \
	  $'Colors:Header\tBackgroundNormal\t'"${bg_rgb}" \
	  $'Colors:Header\tForegroundNormal\t'"${fg_rgb}" \
	  $'Colors:Header\tDecorationFocus\t'"${accent_rgb}" \
	  $'Colors:Header\tDecorationHover\t'"${hover_rgb}" \
	  $'Colors:Tooltip\tBackgroundAlternate\t'"${bg_rgb}" \
	  $'Colors:Tooltip\tBackgroundNormal\t'"${bg_rgb}" \
	  $'Colors:Tooltip\tForegroundNormal\t'"${fg_rgb}" \
	  $'Colors:Complementary\tBackgroundAlternate\t'"${bg_rgb}" \
	  $'Colors:Complementary\tBackgroundNormal\t'"${bg_rgb}" \
	  $'Colors:Complementary\tForegroundNormal\t'"${fg_rgb}"
}

write_kdeglobals_palette() {
  local -a kdeglobals_entries=(
	  $'Colors:View\tBackgroundAlternate\t'"${bg_rgb}"
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
    $'Colors:Selection\tForegroundNormal\t'"${selection_fg_rgb}"
    $'Colors:Selection\tForegroundActive\t'"${selection_fg_rgb}"
    $'Colors:Selection\tForegroundInactive\t'"${inactive_selection_fg_rgb}"
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
  if ! reload_output="$(hyprshell shaders --reload --quiet 2>&1)"; then
    print_log -sec "hyprshell" -warn "reload" "shader reload failed"
    return 1
  fi

  if grep -qi "error" <<<"${reload_output}"; then
    print_log -sec "hyprshell" -warn "reload" "shader reload reported errors"
    return 1
  fi

  [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -sec "hyprshell" -stat "reload" "shaders"
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
    color_hash="${bg_rgb}|${fg_rgb}|${accent_rgb}|${selection_fg_rgb}|${inactive_selection_fg_rgb}|${ICON_THEME:-}|${kde_scheme_name}"
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
