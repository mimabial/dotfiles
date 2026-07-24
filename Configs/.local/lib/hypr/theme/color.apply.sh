#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# Subsystem inputs:
#   selected_color_source, selected_color_mode - active palette policy
#   background, foreground   - pywal palette, sourced by color.finalize.sh
#   color4, color5           - pywal palette accent slots
: "${selected_color_source-}" "${selected_color_mode-}" "${background-}" "${foreground-}" "${color4-}" "${color5-}"
#
# color.apply.sh - Apply generated colors to applications
#
# OVERVIEW:
#   Orchestrates the application of pywal16-generated colors to various
#   applications (terminals, waybar, etc.). File-generating theming
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
#   - ini_write function from core/system.sh

# Primary and secondary theming scripts are defined here so color-sync.sh does
# not need to shadow the same orchestration logic.
declare -ga APP_THEMING_SCRIPTS=(
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
  local rmpc_reload="${LIB_DIR}/hypr/theme/lib/rmpc.reload.bash"

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
      [[ -r "${rmpc_reload}" ]] && bash "${rmpc_reload}"
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

# Convert #RRGGBB to R,G,B (KDE color schemes use comma-separated rgb).
hex_to_rgb() {
  local hex="${1#\#}"

  [[ ! "${hex}" =~ ^[0-9A-Fa-f]{6}$ ]] && {
    echo "0,0,0"
    return 1
  }

  printf "%d,%d,%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Strip inline ";" comments and surrounding whitespace from a raw hex value.
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

post_updates() {
  reload_hypr_shaders
}
