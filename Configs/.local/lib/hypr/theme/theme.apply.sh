#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

for theme_apply_lib in \
  "${LIB_DIR}/hypr/theme/lib/desktop.sync.bash" \
  "${LIB_DIR}/hypr/theme/color.apply.sh" \
  "${LIB_DIR}/hypr/theme/lib/apply.phase_d.bash" \
  "${LIB_DIR}/hypr/theme/pairs.sh" \
  "${LIB_DIR}/hypr/fonts/font.sync.lib.bash"; do
  [[ -r "${theme_apply_lib}" ]] || {
    print_log -sec "theme.apply" -err "source" "missing ${theme_apply_lib}"
    exit 1
  }
  # shellcheck source=/dev/null
  source "${theme_apply_lib}" || exit 1
done
unset theme_apply_lib

THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"

theme_apply_lock_fd=""
theme_apply_lock_owned=0
theme_apply_desktop_state_prepared=0
theme_apply_job_log_dir=""
theme_apply_job_failed=0
theme_apply_preserve_job_logs=0
theme_apply_quiet=false
theme_apply_generation=""
theme_apply_started_ms=""
declare -ga theme_apply_job_names=()
declare -ga theme_apply_job_pids=()
declare -ga theme_apply_job_required=()
declare -ga theme_apply_color_sync_args=()

theme_apply_timing_enabled() {
  [[ "${HYPR_THEME_TIMING:-0}" == "1" || "${LOG_LEVEL:-}" == "debug" ]]
}

theme_apply_now_ms() {
  local now="${EPOCHREALTIME/./}"
  printf '%s\n' "${now:0:13}"
}

theme_apply_log_timing() {
  local name="$1"
  local duration_ms="$2"
  local rc="${3:-0}"

  theme_apply_timing_enabled || return 0
  print_log -sec "theme.apply" -stat "timing" "${name}: ${duration_ms}ms rc=${rc}"
}

theme_apply_timed_call() {
  local name="$1"
  shift

  local start_ms=""
  local end_ms=""
  local rc=0

  start_ms="$(theme_apply_now_ms)"
  "$@"
  rc=$?
  end_ms="$(theme_apply_now_ms)"
  theme_apply_log_timing "${name}" "$((end_ms - start_ms))" "${rc}"
  return "${rc}"
}

theme_apply_elapsed_label() {
  local now_ms=""
  local elapsed_ms=0
  local centiseconds=0

  [[ "${theme_apply_started_ms:-}" =~ ^[0-9]+$ ]] || return 1
  now_ms="$(theme_apply_now_ms)"
  elapsed_ms=$((now_ms - theme_apply_started_ms))
  [[ "${elapsed_ms}" -ge 0 ]] || elapsed_ms=0
  centiseconds=$(((elapsed_ms + 5) / 10))
  printf '%d.%02ds' "$((centiseconds / 100))" "$((centiseconds % 100))"
}

theme_apply_acquire_update_lock() {
  [[ "${theme_apply_lock_owned}" -eq 1 ]] && return 0
  exec {theme_apply_lock_fd}>"${THEME_UPDATE_LOCK}" || return 1
  flock "${theme_apply_lock_fd}" || {
    exec {theme_apply_lock_fd}>&-
    theme_apply_lock_fd=""
    return 1
  }
  theme_apply_lock_owned=1
}

theme_apply_release_update_lock() {
  [[ "${theme_apply_lock_owned}" -eq 1 ]] || return 0
  flock -u "${theme_apply_lock_fd}" 2>/dev/null || true
  exec {theme_apply_lock_fd}>&-
  theme_apply_lock_fd=""
  theme_apply_lock_owned=0
}

theme_apply_cleanup() {
  local exit_code="${1:-$?}"

  theme_apply_release_update_lock || true
  if [[ -n "${theme_apply_job_log_dir}" && -d "${theme_apply_job_log_dir}" ]]; then
    if [[ "${exit_code}" -eq 0 && "${theme_apply_job_failed}" -eq 0 && "${theme_apply_preserve_job_logs}" -eq 0 ]]; then
      rm -rf -- "${theme_apply_job_log_dir}"
    else
      print_log -sec "theme.apply" -warn "job-logs" "kept ${theme_apply_job_log_dir}"
    fi
  fi
  return "${exit_code}"
}

theme_apply_prepare_desktop_state() {
  [[ "${theme_apply_desktop_state_prepared}" -eq 1 ]] && return 0
  theme_desktop_prepare_state || return 1
  theme_apply_desktop_state_prepared=1
}

theme_apply_commit_theme_metadata() {
  local staged_file="${HYPR_THEME_METADATA_FILE:-}"
  local live_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.meta"
  local lua_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.lua"
  local converter="${LIB_DIR}/hypr/util/hypr-to-lua.py"

  [[ -n "${staged_file}" && -f "${staged_file}" ]] || return 0
  mkdir -p "$(dirname "${live_file}")" || return 1

  if [[ -f "${live_file}" ]] && cmp -s "${staged_file}" "${live_file}"; then
    rm -f -- "${staged_file}" || return 1
  else
    mv -f -- "${staged_file}" "${live_file}" || return 1
  fi

  HYPR_THEME_METADATA_FILE="${live_file}"
  export HYPR_THEME_METADATA_FILE

  [[ -x "${converter}" ]] || return 1
  "${converter}" --input "${live_file}" --output "${lua_file}" --set "HYPR_THEME=${HYPR_THEME}"
}

theme_apply_current_icon_theme() {
  local value=""

  if command -v gsettings >/dev/null 2>&1; then
    value="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true)"
    value="${value#\'}"
    value="${value%\'}"
  fi

  if [[ -z "${value}" ]]; then
    local xsettings_conf="${XDG_CONFIG_HOME:-$HOME/.config}/xsettingsd/xsettingsd.conf"
    [[ -r "${xsettings_conf}" ]] && value="$(
      sed -n 's/^Net\/IconThemeName[[:space:]]*"\(.*\)"$/\1/p' "${xsettings_conf}" | head -n1
    )"
  fi

  printf '%s' "${value}"
}

theme_apply_write_dunst_runtime() {
  local r="${LIB_DIR}/hypr/render/dunst.py"
  [[ -x "${r}" ]] || return 1
  "${r}"
}

theme_apply_prepare_job_log_dir() {
  [[ -n "${theme_apply_job_log_dir}" && -d "${theme_apply_job_log_dir}" ]] && return 0

  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/hypr" || return 1
  theme_apply_job_log_dir="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/hypr/theme.apply.jobs.XXXXXX")"
}

theme_apply_reset_jobs() {
  theme_apply_job_names=()
  theme_apply_job_pids=()
  theme_apply_job_required=()
}

theme_apply_next_generation() {
  local current_generation=""
  local next_generation=1

  current_generation="$(state_get "theme_apply_generation" "0" 2>/dev/null || printf '0')"
  [[ "${current_generation}" =~ ^[0-9]+$ ]] || current_generation=0
  next_generation=$((current_generation + 1))
  state_set "theme_apply_generation" "${next_generation}" "staterc" || return 1
  theme_apply_generation="${next_generation}"
  export HYPR_THEME_APPLY_GENERATION="${theme_apply_generation}"
  theme_apply_cancel_previous_phase_d_jobs
}

theme_apply_generation_is_current() {
  local current_generation=""

  [[ -n "${theme_apply_generation}" ]] || return 0
  current_generation="$(state_get "theme_apply_generation" "0" 2>/dev/null || printf '0')"
  [[ "${current_generation}" == "${theme_apply_generation}" ]]
}

theme_apply_start_job() {
  local job_log_dir="$1"
  local name="$2"
  local required="$3"
  local fn="$4"
  shift 4

  local log_file=""
  local status_file=""

  [[ -n "${job_log_dir}" && -d "${job_log_dir}" ]] || return 1
  log_file="${job_log_dir}/${name}.log"
  status_file="${job_log_dir}/${name}.status"

  (
    local start_ms=""
    local end_ms=""
    local rc=0

    start_ms="$(theme_apply_now_ms)"
    "${fn}" "$@"
    rc=$?
    end_ms="$(theme_apply_now_ms)"
    {
      printf 'rc=%s\n' "${rc}"
      printf 'duration_ms=%s\n' "$((end_ms - start_ms))"
    } >"${status_file}"
    exit "${rc}"
  ) >"${log_file}" 2>&1 &

  theme_apply_job_names+=("${name}")
  theme_apply_job_required+=("${required}")
  theme_apply_job_pids+=("$!")
}

theme_apply_log_job_failure() {
  local name="$1"
  local log_file="$2"
  local line=""
  local logged=0

  [[ -s "${log_file}" ]] || return 0
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    print_log -sec "theme.apply" -warn "${name}" "${line}"
    logged=$((logged + 1))
    [[ "${logged}" -ge 6 ]] && break
  done <"${log_file}"
}

theme_apply_wait_jobs() {
  local job_log_dir="$1"
  local i=""
  local name=""
  local pid=""
  local required=""
  local rc=0
  local status_file=""
  local log_file=""
  local duration_ms="0"
  local failed=0

  for i in "${!theme_apply_job_pids[@]}"; do
    name="${theme_apply_job_names[$i]}"
    pid="${theme_apply_job_pids[$i]}"
    required="${theme_apply_job_required[$i]}"
    status_file="${job_log_dir}/${name}.status"
    log_file="${job_log_dir}/${name}.log"

    wait "${pid}"
    rc=$?

    if theme_apply_timing_enabled && [[ -f "${status_file}" ]]; then
      duration_ms="$(awk -F= '$1 == "duration_ms" {print $2; exit}' "${status_file}")"
      [[ -n "${duration_ms}" ]] || duration_ms="0"
    fi
    theme_apply_log_timing "job:${name}" "${duration_ms}" "${rc}"

    if [[ "${rc}" -ne 0 ]]; then
      theme_apply_job_failed=1
      print_log -sec "theme.apply" -warn "${name}" "job failed (${rc})"
      theme_apply_log_job_failure "${name}" "${log_file}"
      [[ "${required}" == "required" ]] && failed=1
    fi
  done

  theme_apply_reset_jobs
  return "${failed}"
}

theme_apply_job_terminal() {
  local terminal_font=""

  terminal_font="$(font_sync_resolve_font_value terminal 2>/dev/null || true)"
  if [[ -n "${terminal_font}" ]]; then
    font_sync_apply_kitty_family "${terminal_font}" || true
    font_sync_apply_alacritty_family "${terminal_font}" || true
  fi

  reload_live_theme_client kitty
}

theme_apply_resolve_current_wallpaper() {
  local wallpaper_link="${HYPR_THEME_DIR}/wall.set"

  if [[ ! -e "${wallpaper_link}" ]]; then
    print_log -sec "theme.apply" -err "wallpaper" "missing ${wallpaper_link}"
    return 1
  fi

  readlink -f -- "${wallpaper_link}" 2>/dev/null \
    || realpath -- "${wallpaper_link}" 2>/dev/null \
    || {
      print_log -sec "theme.apply" -err "wallpaper" "failed to resolve ${wallpaper_link}"
      return 1
    }
}

theme_apply_display_wallpaper() {
  local -a wallpaper_env=(
    WALLPAPER_SKIP_COLORS=1
    WALLPAPER_SKIP_HYPRLOCK_BACKGROUND=1
    WALLPAPER_SKIP_POST_APPLY=1
    WALLPAPER_SKIP_PRECACHE=1
  )

  env "${wallpaper_env[@]}" \
    "${LIB_DIR}/hypr/wallpaper.sh" display --global --no-notify
}

theme_apply_notify_wallpaper_detached() {
  local notify_body="Theme: ${HYPR_THEME}"
  local elapsed_label=""

  if elapsed_label="$(theme_apply_elapsed_label 2>/dev/null)"; then
    notify_body+=$'\n'"Time: ${elapsed_label}"
  fi

  local -a notify_cmd=(
    "${LIB_DIR}/hypr/wallpaper.sh"
    notify
    --global
    --notify-body
    "${notify_body}"
  )

  if command -v setsid >/dev/null 2>&1; then
    setsid "${notify_cmd[@]}" >/dev/null 2>&1 &
  else
    nohup "${notify_cmd[@]}" >/dev/null 2>&1 &
  fi
  disown "$!" 2>/dev/null || true
}

theme_apply_sync_theme_color_variant() {
  # Keep phase-D's desktop color scheme aligned with the applied palette.
  local palette="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/active-palette.json"
  command -v jq >/dev/null 2>&1 || return 0
  [[ -r "${palette}" ]] || return 0
  local mode=""
  mode="$(jq -r '.background // empty' "${palette}" 2>/dev/null || true)"
  [[ "${mode}" =~ ^(dark|light)$ ]] || return 0
  state_set "BACKGROUND_MODE" "${mode}" "staterc" 2>/dev/null || return 1
  state_set_color_variant "${mode}"
}

theme_apply_run_color_sync() {
  local wallpaper_path="$1"
  local hypr_theme_cmd=""
  local variant=""
  local arg=""
  local -a hypr_theme_args=()

  hypr_theme_cmd="$(command -v hypr-theme 2>/dev/null || true)"
  [[ -n "${hypr_theme_cmd}" ]] || hypr_theme_cmd="${HOME}/.local/bin/hypr-theme"
  if [[ ! -x "${hypr_theme_cmd}" ]]; then
    print_log -sec "theme.apply" -err "hypr-theme" "command not found"
    return 1
  fi

  for arg in "${theme_apply_color_sync_args[@]}"; do
    case "${arg}" in
      --regen | --force-regenerate) hypr_theme_args+=(--regen) ;;
      --no-cache) hypr_theme_args+=(--no-cache) ;;
    esac
  done

  if [[ "${selected_color_source}" == "theme" ]]; then
    HYPR_THEME_DEFER_CLIENTS=1 "${hypr_theme_cmd}" apply "${hypr_theme_args[@]}" "${HYPR_THEME}"
    local apply_rc=$?
    [[ "${apply_rc}" -eq 0 ]] || return "${apply_rc}"
    theme_apply_sync_theme_color_variant
    return
  fi

  variant="$(theme_polarity "${HYPR_THEME}")"

  state_set "BACKGROUND_MODE" "${variant}" "staterc" || return 1
  state_set_color_variant "${variant}" || return 1

  HYPR_THEME_DEFER_CLIENTS=1 "${hypr_theme_cmd}" wallpaper "${hypr_theme_args[@]}" --variant "${variant}" "${wallpaper_path}"
}

theme_apply_job_desktop() {
  theme_apply_prepare_desktop_state || return 1
  theme_desktop_write_dconf_content
}

theme_apply_job_dunst() {
  theme_apply_write_dunst_runtime || {
    print_log -sec "theme.apply" -warn "dunst" "write failed"
    return 1
  }
}

trap 'theme_apply_cleanup "$?"' EXIT

if [[ "${1:-}" == "--theme-envelope" ]]; then
  shift
  theme_apply_run_envelope_cli "$@"
  exit $?
fi

theme_apply_usage() {
  printf '%s\n' "Usage: $(basename "$0") [--quiet] [--regen|--force-regenerate] [--no-cache]"
}

quiet=false
while (($#)); do
  case "$1" in
    --quiet) quiet=true ;;
    --regen | --force-regenerate)
      theme_apply_color_sync_args+=(--force-regenerate)
      export FORCE_COLOR_REGEN=1
      ;;
    --no-cache)
      theme_apply_color_sync_args+=(--no-cache)
      export HYPR_WAL_CACHE_ENABLE=0
      ;;
    -h | --help)
      theme_apply_usage
      exit 0
      ;;
    *)
      theme_apply_usage >&2
      exit 1
      ;;
  esac
  shift
done
theme_apply_quiet="${quiet}"
export theme_apply_quiet
theme_apply_started_ms="$(theme_apply_now_ms)"

wallpaper_path=""
if [[ "${selected_color_source}" == "theme" ]]; then
  :
else
  wallpaper_path="$(theme_apply_resolve_current_wallpaper)" || exit 1
fi

theme_apply_timed_call "generation" theme_apply_next_generation || exit 1
theme_apply_timed_call "lock" theme_apply_acquire_update_lock || exit 1
theme_apply_timed_call "metadata_commit" theme_apply_commit_theme_metadata || exit 1
theme_apply_timed_call "color_sync" theme_apply_run_color_sync "${wallpaper_path}" || exit 1
theme_apply_prepare_job_log_dir || exit 1
theme_apply_reset_jobs
theme_apply_start_job "${theme_apply_job_log_dir}" "wallpaper_display" best_effort theme_apply_display_wallpaper || true
theme_apply_start_job "${theme_apply_job_log_dir}" "desktop" required theme_apply_job_desktop || exit 1
theme_apply_start_job "${theme_apply_job_log_dir}" "terminal" required theme_apply_job_terminal || exit 1
theme_apply_start_job "${theme_apply_job_log_dir}" "dunst" best_effort theme_apply_job_dunst || true
theme_apply_wait_jobs "${theme_apply_job_log_dir}" || theme_apply_required_rc=$?
theme_apply_timed_call "envelope_launch" theme_apply_start_envelope || true
[[ -z "${theme_apply_required_rc:-}" ]] || exit "${theme_apply_required_rc}"
theme_apply_release_update_lock
theme_apply_notify_wallpaper_detached || true
