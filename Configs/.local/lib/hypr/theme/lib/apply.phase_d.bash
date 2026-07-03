#!/usr/bin/env bash
# Sourced module; strict mode is owned by theme.apply.sh.
#
# apply.phase_d.bash — phase-D infrastructure and best-effort jobs.
#
# Phase model:
#   Phase A (foreground, in theme.apply.sh): color-sync runs, theme metadata
#   commits, submits the wallpaper display, runs hyprctl reload, then a small
#   required job pool updates the immediately visible clients. Waybar CSS is
#   hot-reloaded by Waybar itself; the foreground path only writes CSS includes
#   and starts Waybar if missing. Dunst and Firefox refreshes are detached
#   best-effort jobs.
#   Phase A holds the theme-update lock end-to-end and is the path the user
#   waits on.
#
#   Phase D (this file): everything best-effort that should not block the
#   foreground. Runs in a detached systemd-run user-slice unit so it survives
#   the foreground exiting and can be cancelled by a newer theme apply.
#   Each phase-D job short-circuits via theme_apply_generation_is_current if
#   a newer generation has started.
#
# Subprocess re-entry: theme.apply.sh re-execs itself with --theme-envelope
# inside the systemd unit. That subprocess sources this file and dispatches
# theme_apply_run_envelope_cli, which bootstraps color.finalize.sh and runs
# the phase-D job pool.
#
# Subsystem inputs (set by theme.apply.sh entrypoint):
#   theme_apply_generation, theme_apply_phase_d_log_dir, theme_apply_quiet,
#   theme_apply_preserve_job_logs, selected_color_mode, thmWall

: "${theme_apply_generation-}" "${theme_apply_quiet-}" \
  "${theme_apply_preserve_job_logs-}" \
  "${selected_color_mode-}" "${thmWall-}"

theme_apply_phase_d_log_dir=""

# --- Phase-D log directory and unit tracking ---

theme_apply_phase_d_prepare_log_dir() {
  local log_root="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/theme.apply.phase-d"

  [[ -n "${theme_apply_phase_d_log_dir}" && -d "${theme_apply_phase_d_log_dir}" ]] && return 0
  mkdir -p "${log_root}" || return 1
  theme_apply_phase_d_log_dir="${log_root}/${theme_apply_generation:-0}.$$"
  mkdir -p "${theme_apply_phase_d_log_dir}" || return 1
}

theme_apply_phase_d_unit_dir() {
  local runtime_dir=""

  runtime_dir="$(hypr_runtime_subdir hypr)" || return 1
  printf '%s/theme.apply.phase-d.units\n' "${runtime_dir}"
}

theme_apply_cancel_phase_d_unit() {
  local unit="$1"

  [[ -n "${unit}" ]] || return 0
  command -v systemctl >/dev/null 2>&1 || return 0

  theme_apply_timing_enabled && print_log -sec "theme.apply" -stat "cancel" "unit:${unit}"
  systemctl --user stop --job-mode=replace-irreversibly --no-block "${unit}" 2>/dev/null || true
  systemctl --user kill --kill-whom=all --signal=SIGKILL --wait "${unit}" 2>/dev/null || true
  systemctl --user reset-failed "${unit}" 2>/dev/null || true
}

theme_apply_cancel_previous_phase_d_jobs() {
  local unit_dir=""
  local handle_file=""
  local base=""
  local generation=""
  local unit=""

  unit_dir="$(theme_apply_phase_d_unit_dir)" || return 0
  mkdir -p "${unit_dir}" || return 0

  while IFS= read -r -d '' handle_file; do
    base="${handle_file##*/}"
    generation="${base%%-*}"
    [[ "${generation}" == "${theme_apply_generation}" ]] && continue
    unit="$(cat -- "${handle_file}" 2>/dev/null || true)"
    rm -f -- "${handle_file}"
    theme_apply_cancel_phase_d_unit "${unit}"
  done < <(find "${unit_dir}" -maxdepth 1 -type f -name '*.unit' -print0 2>/dev/null)
}

theme_apply_phase_d_prune_log_dirs() {
  local current_log_dir="${1:-}"
  local log_root="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/theme.apply.phase-d"
  local keep="${HYPR_THEME_PHASE_D_LOG_KEEP:-20}"
  local victim=""

  [[ -d "${log_root}" ]] || return 0
  [[ "${keep}" =~ ^[0-9]+$ ]] || keep=20
  [[ "${keep}" -gt 0 ]] || return 0

  while IFS= read -r victim; do
    [[ -z "${victim}" ]] && continue
    [[ -n "${current_log_dir}" && "${victim}" == "${current_log_dir}" ]] && continue
    rm -rf -- "${victim}" 2>/dev/null || true
  done < <(
    find "${log_root}" -mindepth 1 -maxdepth 1 -type d -regex '.*/[0-9]+\.[0-9]+' -printf '%T@\t%p\n' 2>/dev/null \
      | sort -rn \
      | tail -n +"$((keep + 1))" \
      | cut -f2-
  )
}

# --- systemd envelope start/run ---

theme_apply_phase_d_systemd_available() {
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 1
  command -v systemd-run >/dev/null 2>&1 || return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

theme_apply_start_envelope() {
  local log_file=""
  local unit_dir=""
  local unit_file=""
  local unit_name=""
  local -a envelope_cmd=()

  theme_apply_phase_d_prepare_log_dir || return 1
  unit_dir="$(theme_apply_phase_d_unit_dir)" || return 1
  mkdir -p "${unit_dir}" || return 1
  unit_file="${unit_dir}/${theme_apply_generation}-envelope.unit"
  log_file="${theme_apply_phase_d_log_dir}/envelope.log"

  envelope_cmd=(
    bash
    "${LIB_DIR}/hypr/theme/theme.apply.sh"
    --theme-envelope
    --generation "${theme_apply_generation}"
    --log-dir "${theme_apply_phase_d_log_dir}"
    --unit-file "${unit_file}"
  )
  [[ "${theme_apply_quiet}" == "true" ]] && envelope_cmd+=(--quiet)

  if ! theme_apply_phase_d_systemd_available; then
    print_log -sec "theme.apply" -warn "envelope" "systemd user manager unavailable"
    return 1
  fi

  unit_name="hyprshell-theme-${theme_apply_generation}.service"
  local -a envelope_env=()
  # systemd-run --user starts with a clean env; forward the regen/cache flags
  # the user passed to theme.switch.sh so the envelope sees them and
  # apply_static_resolved_if_needed can honor --regen/--no-cache.
  [[ -n "${FORCE_COLOR_REGEN:-}" ]] && envelope_env+=(-E "FORCE_COLOR_REGEN=${FORCE_COLOR_REGEN}")
  [[ -n "${HYPR_WAL_CACHE_ENABLE:-}" ]] && envelope_env+=(-E "HYPR_WAL_CACHE_ENABLE=${HYPR_WAL_CACHE_ENABLE}")
  if systemd-run --user --quiet --no-block --collect \
      --slice="${HYPR_THEME_PHASE_D_SLICE:-background.slice}" \
      --unit="${unit_name}" \
      --description="hyprshell theme envelope gen=${theme_apply_generation}" \
      -p "CPUWeight=${HYPR_THEME_PHASE_D_CPU_WEIGHT:-20}" \
      -p "IOWeight=${HYPR_THEME_PHASE_D_IO_WEIGHT:-20}" \
      -p "StandardOutput=append:${log_file}" \
      -p "StandardError=append:${log_file}" \
      "${envelope_env[@]}" \
      "${envelope_cmd[@]}"; then
    printf '%s\n' "${unit_name}" >"${unit_file}" 2>/dev/null || true
    return 0
  fi

  print_log -sec "theme.apply" -warn "envelope" "systemd-run failed"
  return 1
}

theme_apply_run_envelope_cli() {
  local log_dir=""
  local unit_file=""
  local quiet="${theme_apply_quiet}"
  local wallpaper_log=""
  local wallpaper_pid=""

  while (($#)); do
    case "$1" in
      --generation)
        shift
        theme_apply_generation="${1:-}"
        export HYPR_THEME_APPLY_GENERATION="${theme_apply_generation}"
        ;;
      --log-dir)
        shift
        log_dir="${1:-}"
        ;;
      --unit-file)
        shift
        unit_file="${1:-}"
        ;;
      --quiet)
        quiet=true
        ;;
      *)
        print_log -sec "theme.apply" -warn "envelope" "unknown arg: $1"
        return 1
        ;;
    esac
    shift
  done

  [[ -n "${log_dir}" ]] || return 1
  theme_apply_preserve_job_logs=1
  mkdir -p "${log_dir}" || return 1
  theme_apply_quiet="${quiet}"
  export theme_apply_quiet
  theme_apply_phase_d_bootstrap || return 1

  wallpaper_log="${log_dir}/wallpaper.log"

  # Wallpaper maintenance runs inside this cgroup; if the unit is stopped,
  # both the wallpaper child and the phase-d jobs die together. The visible
  # backend submit already happened in phase A.
  theme_apply_envelope_launch_wallpaper "${wallpaper_log}" &
  wallpaper_pid=$!

  if theme_apply_generation_is_current; then
    theme_apply_phase_d_run_jobs "${log_dir}"
  fi

  wait "${wallpaper_pid}" 2>/dev/null || true

  theme_apply_phase_d_prune_log_dirs "${log_dir}" 2>/dev/null || true
  [[ -n "${unit_file}" ]] && rm -f -- "${unit_file}" 2>/dev/null || true
}

theme_apply_envelope_launch_wallpaper() {
  local wallpaper_log="$1"
  local -a wallpaper_args=(
    resume
    --global
    --no-notify
  )
  local -a wallpaper_env=(
    "WALLPAPER_SYNC_APPLY=1"
    WALLPAPER_SKIP_BACKEND_APPLY=1
    WALLPAPER_SKIP_COLORS=1
    WALLPAPER_SKIP_POST_APPLY=1
    WALLPAPER_SKIP_PRECACHE=1
  )
  # WALLPAPER_SKIP_HYPRLOCK_BACKGROUND is intentionally NOT set: we want
  # the wallpaper resume to refresh the hyprlock background itself, right
  # after it updates the wall.set symlink. WALLPAPER_SKIP_BACKEND_APPLY keeps
  # this maintenance pass from submitting a second late visible transition.

  if [[ -n "${wallpaper_log}" ]]; then
    env "${wallpaper_env[@]}" "${LIB_DIR}/hypr/wallpaper.sh" "${wallpaper_args[@]}" \
      </dev/null >>"${wallpaper_log}" 2>&1
  else
    env "${wallpaper_env[@]}" "${LIB_DIR}/hypr/wallpaper.sh" "${wallpaper_args[@]}" \
      </dev/null >/dev/null 2>&1
  fi
}

# --- Phase-D bootstrap and job pool ---

theme_apply_phase_d_bootstrap() {
  local module=""
  local module_path=""
  local -a modules=(
    color.finalize.sh
  )

  WAL_XDG_CACHE_HOME="${WAL_XDG_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}}"
  WAL_CACHE="${WAL_CACHE:-${WAL_XDG_CACHE_HOME}/wal}"
  export WAL_XDG_CACHE_HOME WAL_CACHE

  for module in "${modules[@]}"; do
    module_path="${LIB_DIR}/hypr/theme/${module}"
    if [[ ! -r "${module_path}" ]]; then
      print_log -sec "theme.apply" -err "phase-d" "missing ${module_path}"
      return 1
    fi
    # shellcheck source=/dev/null
    source "${module_path}" || return 1
  done
}

theme_apply_phase_d_run_jobs() {
  local job_log_dir="$1"

  [[ -n "${job_log_dir}" && -d "${job_log_dir}" ]] || return 1
  theme_apply_reset_jobs
  theme_apply_start_job "${job_log_dir}" "secondary_updates" best_effort theme_apply_job_secondary_updates || true
  theme_apply_start_job "${job_log_dir}" "static_desktop" best_effort theme_apply_job_static_desktop || true
  theme_apply_start_job "${job_log_dir}" "tmux" best_effort theme_apply_job_tmux || true
  theme_apply_start_job "${job_log_dir}" "rmpc" best_effort theme_apply_job_rmpc || true
  theme_apply_start_job "${job_log_dir}" "nvim" best_effort theme_apply_job_nvim || true
  theme_apply_start_job "${job_log_dir}" "runtime_desktop" best_effort theme_apply_job_runtime_desktop || true
  theme_apply_start_job "${job_log_dir}" "backend_wallpaper_links" best_effort theme_apply_job_backend_wallpaper_links || true
  theme_apply_start_job "${job_log_dir}" "wallpaper_thumbs" best_effort theme_apply_job_wallpaper_thumbs || true
  # hyprlock_background is intentionally absent: the wallpaper resume in
  # this same envelope handles it (see envelope_launch_wallpaper above).
  # Running it as a parallel job raced with the wallpaper symlink update.
  theme_apply_wait_jobs "${job_log_dir}" || true

  # The icon-theme sinks (gsettings, gtk settings.ini, xsettingsd + HUP) are now
  # written and settled by the desktop jobs above; do the icon-aware waybar
  # restart last so the bar reloads with the correct taskbar/tray icons.
  theme_apply_phase_d_waybar_icon_sync || true
}

# Authoritative waybar restart for icon-theme changes. Runs after the phase-D
# wait barrier, i.e. once the icon sinks are live, so it reads the correct icon
# theme instead of racing it (unlike the old synchronous restart in
# theme_apply_job_waybar). Restarts only when the icon theme actually changed
# and advances the state cache.
theme_apply_phase_d_waybar_icon_sync() {
  theme_apply_generation_is_current || return 0

  local current_icon_theme="" cached_icon_theme=""
  current_icon_theme="$(theme_apply_current_icon_theme)"
  cached_icon_theme="$(state_get "waybar_icon_theme" "" 2>/dev/null || true)"

  if hypr_user_pgrep -x waybar >/dev/null 2>&1 \
    && [[ -n "${current_icon_theme}" && "${current_icon_theme}" == "${cached_icon_theme}" ]]; then
    return 0
  fi

  theme_apply_restart_waybar_direct || {
    print_log -sec "theme.apply" -warn "waybar" "icon-theme restart failed"
    return 1
  }

  [[ -n "${current_icon_theme}" ]] \
    && state_set "waybar_icon_theme" "${current_icon_theme}" "staterc" 2>/dev/null || true
}

theme_apply_run_phase_d_script() {
  local lock_key="$1"
  local script_rel="$2"
  local script_path="${LIB_DIR}/hypr/${script_rel}"

  theme_apply_generation_is_current || return 0
  [[ -f "${script_path}" ]] || return 0
  HYPR_THEME_APPLY_GENERATION="${theme_apply_generation}" \
    HYPR_THEME_PHASE_D_LOCK_KEY="${lock_key}" \
    bash "${script_path}"
}

# --- Helpers used by phase-D jobs ---

theme_apply_sync_runtime_desktop_state() {
  local quiet="${1:-false}"

  theme_apply_prepare_desktop_state || return 1

  if [[ "${quiet}" == "true" ]]; then
    if (
      THEME_DESKTOP_SYNC_LOG_DCONF=0 theme_desktop_apply_runtime_resolved && theme_desktop_set_cursor_async
    ) >/dev/null 2>&1; then
      return 0
    fi

    return 1
  fi

  theme_desktop_apply_runtime_resolved && theme_desktop_set_cursor_async
}

theme_apply_run_static_desktop_sync() {
  theme_apply_prepare_desktop_state && theme_desktop_apply_static_resolved_if_needed
}

theme_apply_sync_nvim_theme() {
  if [[ -x "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh" ]]; then
    "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh"
  fi
}

theme_apply_enqueue_wallpaper_thumbs() {
  local -a cache_args=()
  local wall=""
  local queue_script=""
  local cache_script=""

  # get_themes is idempotent and populates thmWall; call it unconditionally so
  # we are not at the mercy of caller scope under set -u.
  get_themes

  for wall in "${thmWall[@]}"; do
    [[ -n "${wall}" ]] || continue
    [[ -r "${wall}" ]] || continue
    cache_args+=(-w "${wall}")
  done

  queue_script="${LIB_DIR}/hypr/wallpaper/wallcache.daemon.sh"
  cache_script="${LIB_DIR}/hypr/wallpaper/wallpaper.cache.sh"
  [[ -x "${queue_script}" || -x "${cache_script}" ]] || return 0
  [[ ${#cache_args[@]} -eq 0 ]] && return 0

  if [[ -x "${queue_script}" ]]; then
    "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
  else
    "${cache_script}" "${cache_args[@]}" &>/dev/null &
  fi
}

theme_apply_sync_backend_wallpaper_links() {
  local file=""
  local base=""

  [[ -d "${WALLPAPER_CURRENT_DIR}" ]] || return 0

  while IFS= read -r -d '' file; do
    base="$(basename "${file}" .png)"
    pkg_installed "${base}" || continue
    "${LIB_DIR}/hypr/wallpaper.sh" link --backend "${base}" >/dev/null 2>&1 || true
  done < <(find -H "${WALLPAPER_CURRENT_DIR}" -maxdepth 1 -type l -name "*.png" -print0)
}

# --- Phase-D job functions ---

theme_apply_job_nvim() {
  theme_apply_generation_is_current || return 0
  theme_apply_sync_nvim_theme
}

theme_apply_job_tmux() {
  theme_apply_generation_is_current || return 0
  reload_live_theme_client tmux
}

theme_apply_job_rmpc() {
  theme_apply_generation_is_current || return 0
  reload_live_theme_client rmpc
}

theme_apply_job_runtime_desktop() {
  theme_apply_generation_is_current || return 0
  theme_apply_sync_runtime_desktop_state "${theme_apply_quiet}" || {
    print_log -sec "theme.apply" -warn "desktop" "runtime sync failed"
    return 1
  }
}

theme_apply_job_static_desktop() {
  theme_apply_generation_is_current || return 0
  theme_apply_run_static_desktop_sync || {
    print_log -sec "theme.apply" -warn "desktop" "static sync failed"
    return 1
  }
}

theme_apply_job_secondary_updates() {
  theme_apply_generation_is_current || return 0
  color_finalize_source_generated_colors || return 1
  color_finalize_export_icon_theme || return 1
  # waybar border-radius already updated synchronously by theme.apply.sh:553.
  ASYNC_POST_UPDATES=1 post_updates >/dev/null 2>&1 || true
}

theme_apply_job_backend_wallpaper_links() {
  theme_apply_generation_is_current || return 0
  theme_apply_sync_backend_wallpaper_links
}

theme_apply_job_wallpaper_thumbs() {
  theme_apply_generation_is_current || return 0
  theme_apply_enqueue_wallpaper_thumbs
}
