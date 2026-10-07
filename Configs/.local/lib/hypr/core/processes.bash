#!/usr/bin/env bash

# MemAvailable is absent on very old kernels, hence the MemTotal fallback.
hypr_read_host_capacity() {
  local -n capacity_cores_ref="$1" capacity_mem_mb_ref="$2"
  local mem_kb=""

  capacity_cores_ref="$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [[ "${capacity_cores_ref}" =~ ^[0-9]+$ ]] || capacity_cores_ref=1

  mem_kb="$(awk '/MemAvailable/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  [[ -n "${mem_kb}" ]] || mem_kb="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  [[ "${mem_kb}" =~ ^[0-9]+$ ]] || mem_kb=0
  capacity_mem_mb_ref=$((mem_kb / 1024))
}

MAGICK_MEM_SHARE=8
MAGICK_MEM_MIN_MB=256
MAGICK_MEM_MAX_MB=1024
MAGICK_MEM_FALLBACK_MB=512
MAGICK_MAP_MIN_MB=512
MAGICK_MAP_MAX_MB=4096
MAGICK_MAX_THREADS=4

hypr_export_magick_limits() {
  local cores="$1" mem_avail_mb="$2"

  if [[ ! "${WALLPAPER_MAGICK_MEM_MB:-}" =~ ^[0-9]+$ ]]; then
    if ((mem_avail_mb > 0)); then
      WALLPAPER_MAGICK_MEM_MB="$(hypr_clamp $((mem_avail_mb / MAGICK_MEM_SHARE)) "${MAGICK_MEM_MIN_MB}" "${MAGICK_MEM_MAX_MB}")"
    else
      WALLPAPER_MAGICK_MEM_MB="${MAGICK_MEM_FALLBACK_MB}"
    fi
  fi
  [[ "${WALLPAPER_MAGICK_MAP_MB:-}" =~ ^[0-9]+$ ]] \
    || WALLPAPER_MAGICK_MAP_MB="$(hypr_clamp $((WALLPAPER_MAGICK_MEM_MB * 2)) "${MAGICK_MAP_MIN_MB}" "${MAGICK_MAP_MAX_MB}")"
  [[ "${WALLPAPER_MAGICK_THREADS:-}" =~ ^[0-9]+$ ]] \
    || WALLPAPER_MAGICK_THREADS="$(hypr_clamp "${cores}" 1 "${MAGICK_MAX_THREADS}")"
  export WALLPAPER_MAGICK_MEM_MB WALLPAPER_MAGICK_MAP_MB WALLPAPER_MAGICK_THREADS
}

hypr_magick_limit_args_into() {
  local -n limit_args_ref="$1"

  limit_args_ref=()
  [[ -z "${WALLPAPER_MAGICK_MEM_MB:-}" ]] || limit_args_ref+=(-limit memory "${WALLPAPER_MAGICK_MEM_MB}MiB")
  [[ -z "${WALLPAPER_MAGICK_MAP_MB:-}" ]] || limit_args_ref+=(-limit map "${WALLPAPER_MAGICK_MAP_MB}MiB")
  [[ -z "${WALLPAPER_MAGICK_THREADS:-}" ]] || limit_args_ref+=(-limit thread "${WALLPAPER_MAGICK_THREADS}")
}

hypr_user_pgrep() {
  pgrep -u "${UID}" "$@"
}

hypr_user_pkill() {
  pkill -u "${UID}" "$@"
}

# PipeWire and BlueZ clients block on a stuck daemon; a call gets this long, and a
# SIGKILL one second after that.
HYPR_DAEMON_CALL_TIMEOUT_S=2

hypr_daemon_call() {
  timeout --kill-after=1s "${HYPR_DAEMON_CALL_TIMEOUT_S}" "$@"
}

# Bitwarden desktop has no lock command and locks only on a ScreenSaver D-Bus signal
# nothing here emits, so quitting it is its lock.
hypr_lock_password_managers() {
  quickshell ipc call bitwarden screenLocked </dev/null >/dev/null 2>&1 &
  hypr_user_pkill -f '^/usr/lib/electron[0-9]*/electron /usr/lib/bitwarden/app\.asar' || true
}
