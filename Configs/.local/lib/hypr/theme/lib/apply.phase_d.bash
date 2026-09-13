#!/usr/bin/env bash
# Sourced module; strict mode is owned by theme.apply.sh.
# Architecture: ../PHASES.md

theme_apply_phase_d_log_dir=""

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

# Detached handles use pid:<session-leader>; unit handles name a cgroup.
theme_apply_cancel_phase_d_handle() {
  local handle="$1"

  [[ -n "${handle}" ]] || return 0
  theme_apply_timing_enabled && print_log -sec "theme.apply" -stat "cancel" "${handle}"

  if [[ "${handle}" == pid:* ]]; then
    kill -TERM -- "-${handle#pid:}" 2>/dev/null || true
    return 0
  fi

  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user stop --job-mode=replace-irreversibly --no-block "${handle}" 2>/dev/null || true
  systemctl --user kill --kill-whom=all --signal=SIGKILL --wait "${handle}" 2>/dev/null || true
  systemctl --user reset-failed "${handle}" 2>/dev/null || true
}

theme_apply_cancel_previous_phase_d_jobs() {
  local unit_dir=""
  local handle_file=""
  local base=""
  local generation=""
  local handle=""

  unit_dir="$(theme_apply_phase_d_unit_dir)" || return 0
  mkdir -p "${unit_dir}" || return 0

  while IFS= read -r -d '' handle_file; do
    base="${handle_file##*/}"
    generation="${base%%-*}"
    [[ "${generation}" == "${theme_apply_generation}" ]] && continue
    IFS= read -r handle <"${handle_file}" || handle=""
    rm -f -- "${handle_file}"
    theme_apply_cancel_phase_d_handle "${handle}"
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
    theme_apply_start_envelope_detached "${log_file}" "${envelope_cmd[@]}"
    return $?
  fi

  unit_name="hyprshell-theme-${theme_apply_generation}.service"
  local -a envelope_env=()
  # Forward cache flags into systemd-run's clean environment.
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
  theme_apply_start_envelope_detached "${log_file}" "${envelope_cmd[@]}"
}

# A separate session survives the foreground and gives cancellation a process group.
theme_apply_start_envelope_detached() {
  local log_file="$1"
  shift

  local -a prio=()
  command -v setsid >/dev/null 2>&1 || {
    print_log -sec "theme.apply" -warn "envelope" "no systemd user manager and no setsid"
    return 1
  }
  command -v ionice >/dev/null 2>&1 && prio=(ionice -c 3)
  command -v nice >/dev/null 2>&1 && prio+=(nice -n "${HYPR_THEME_PHASE_D_NICE:-10}")

  setsid "${prio[@]}" "$@" --detached </dev/null >>"${log_file}" 2>&1 &
  disown "$!" 2>/dev/null || true
}

theme_apply_run_envelope_cli() {
  local log_dir=""
  local unit_file=""
  local quiet="${theme_apply_quiet}"
  local detached=0
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
      --detached)
        detached=1
        ;;
      *)
        print_log -sec "theme.apply" -warn "envelope" "unknown arg: $1"
        return 1
        ;;
    esac
    shift
  done

  [[ -n "${log_dir}" ]] || return 1
  # setsid may fork, so only the envelope knows the process-group id.
  if [[ "${detached}" -eq 1 && -n "${unit_file}" ]]; then
    printf 'pid:%s\n' "$$" >"${unit_file}" 2>/dev/null || true
  fi
  theme_apply_preserve_job_logs=1
  mkdir -p "${log_dir}" || return 1
  theme_apply_quiet="${quiet}"
  export theme_apply_quiet
  theme_apply_phase_d_bootstrap || return 1

  wallpaper_log="${log_dir}/wallpaper.log"

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
  # Resume refreshes hyprlock; skip only the already-submitted visible transition.

  if [[ -n "${wallpaper_log}" ]]; then
    env "${wallpaper_env[@]}" "${LIB_DIR}/hypr/wallpaper.sh" "${wallpaper_args[@]}" \
      </dev/null >>"${wallpaper_log}" 2>&1
  else
    env "${wallpaper_env[@]}" "${LIB_DIR}/hypr/wallpaper.sh" "${wallpaper_args[@]}" \
      </dev/null >/dev/null 2>&1
  fi
}

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
  local desktop_ready=0

  [[ -n "${job_log_dir}" && -d "${job_log_dir}" ]] || return 1
  if theme_apply_prepare_desktop_state; then
    desktop_ready=1
  else
    print_log -sec "theme.apply" -warn "desktop" "state resolution failed"
  fi
  theme_apply_reset_jobs
  theme_apply_start_phase_d_job "${job_log_dir}" secondary_updates theme_apply_secondary_updates
  [[ "${desktop_ready}" -eq 0 ]] || theme_apply_start_phase_d_job "${job_log_dir}" static_desktop theme_apply_run_static_desktop_sync
  theme_apply_start_phase_d_job "${job_log_dir}" tmux reload_live_theme_client tmux
  theme_apply_start_phase_d_job "${job_log_dir}" rmpc reload_live_theme_client rmpc
  theme_apply_start_phase_d_job "${job_log_dir}" nvim theme_apply_sync_nvim_theme
  [[ "${desktop_ready}" -eq 0 ]] || theme_apply_start_phase_d_job "${job_log_dir}" runtime_desktop theme_apply_sync_runtime_desktop_state "${theme_apply_quiet}"
  theme_apply_start_phase_d_job "${job_log_dir}" backend_wallpaper_links theme_apply_sync_backend_wallpaper_links
  theme_apply_start_phase_d_job "${job_log_dir}" wallpaper_thumbs theme_apply_enqueue_wallpaper_thumbs
  theme_apply_wait_jobs "${job_log_dir}" || true

  theme_apply_phase_d_quickshell_icon_sync || true
}

# qt6ct caches icons at process start; leave a stopped Quickshell stopped.
theme_apply_phase_d_quickshell_icon_sync() {
  theme_apply_generation_is_current || return 0

  local current_icon_theme="" cached_icon_theme=""
  current_icon_theme="$(theme_apply_current_icon_theme)"
  cached_icon_theme="$(state_get "quickshell_icon_theme" "" 2>/dev/null || true)"

  if [[ -n "${current_icon_theme}" && "${current_icon_theme}" == "${cached_icon_theme}" ]]; then
    return 0
  fi

  if hypr_svc_user is-active hyprland-quickshell; then
    hypr_svc_user restart hyprland-quickshell || {
      print_log -sec "theme.apply" -warn "quickshell" "icon-theme restart failed"
      return 1
    }
  elif hypr_user_pgrep -x quickshell >/dev/null 2>&1; then
    print_log -sec "theme.apply" -warn "quickshell" "running outside hyprland-quickshell.service; icons follow after manual restart"
  fi

  [[ -n "${current_icon_theme}" ]] \
    && state_set "quickshell_icon_theme" "${current_icon_theme}" "staterc" 2>/dev/null || true
}

theme_apply_sync_runtime_desktop_state() {
  local quiet="${1:-false}"

  if [[ "${quiet}" == "true" ]]; then
    if (
      THEME_DESKTOP_SYNC_LOG_DCONF=0 theme_desktop_apply_runtime_resolved && theme_desktop_apply_cursor_theme
    ) >/dev/null 2>&1; then
      return 0
    fi

    return 1
  fi

  theme_desktop_apply_runtime_resolved && theme_desktop_apply_cursor_theme
}

theme_apply_run_static_desktop_sync() {
  theme_desktop_apply_static_resolved_if_needed
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

theme_apply_run_if_current() {
  theme_apply_generation_is_current || return 0
  "$@"
}

theme_apply_start_phase_d_job() {
  local job_log_dir="$1" name="$2"
  shift 2
  theme_apply_start_job "${job_log_dir}" "${name}" best_effort theme_apply_run_if_current "$@" || true
}

theme_apply_secondary_updates() {
  color_finalize_source_generated_colors || return 1
  color_finalize_export_icon_theme || return 1
  ASYNC_POST_UPDATES=1 post_updates >/dev/null 2>&1 || true
}
