#!/usr/bin/env bash

color_plan_resolve_theme_context() {
  selected_color_mode="${selected_color_mode:-1}"
  resolved_color_variant="${resolved_color_variant:-dark}"
  SKIP_WAYBAR_UPDATE="${SKIP_WAYBAR_UPDATE:-0}"

  if [[ -z "${MODE_OVERRIDE}" ]] && [[ "${selected_color_mode}" == "1" ]] && [[ -f "${HYPR_STATE_HOME}/color_variant" ]]; then
    resolved_color_variant="$(cat "${HYPR_STATE_HOME}/color_variant")"
  fi

  if [[ -z "${HYPR_THEME}" ]]; then
    local wal_conf="${HYPR_CONFIG_HOME}/themes/wal.conf"
    if [[ -f "${wal_conf}" ]]; then
      HYPR_THEME="$(grep '^\$HYPR_THEME=' "${wal_conf}" | cut -d'=' -f2)"
    fi

    if [[ -z "${HYPR_THEME}" ]] && [[ -d "${HYPR_CONFIG_HOME}/themes" ]]; then
      HYPR_THEME="$(find "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d | sort | head -1 | xargs basename)"
    fi
  fi

  if [[ -z "${HYPR_THEME}" ]]; then
    print_log -sec "theme" -err "detect" "unable to resolve active theme"
    exit 1
  fi

  if [[ -n "${HYPR_THEME}" && -z "${HYPR_THEME_DIR}" ]]; then
    export HYPR_THEME="${HYPR_THEME}"
    export HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
    print_log -sec "theme" -stat "detected" "${HYPR_THEME}"
  fi

  case "${selected_color_mode}" in
    2) resolved_color_variant="dark" ;;
    3) resolved_color_variant="light" ;;
  esac

  if [[ -n "${MODE_OVERRIDE}" ]]; then
    case "${MODE_OVERRIDE}" in
      dark | light) resolved_color_variant="${MODE_OVERRIDE}" ;;
      *) print_log -sec "pywal16" -warn "mode" "invalid override: ${MODE_OVERRIDE}" ;;
    esac
  fi

  THEME_KITTY_FILE="${HYPR_THEME_DIR}/kitty.theme"
  THEME_BG=""
  THEME_FG=""
  THEME_CURSOR=""
  THEME_COLORS=()
}

color_plan_prepare_wal_cache_root() {
  WAL_XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

  if [[ "${CACHE_ONLY}" -eq 1 ]]; then
    local cache_only_root_base="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
    CACHE_ONLY_ROOT="$(mktemp -d -p "${cache_only_root_base}" "wal-cache-only.XXXXXXXX")" || {
      print_log -sec "pywal16" -err "cache" "temp dir failed"
      exit 1
    }
    WAL_XDG_CACHE_HOME="${CACHE_ONLY_ROOT}"
  fi

  WAL_CACHE="${WAL_XDG_CACHE_HOME}/wal"
  mkdir -p "${WAL_CACHE}"
}

color_plan_init_cache_controls() {
  CACHE_CLEANUP_ENABLED="${HYPR_WAL_CACHE_CLEANUP:-1}"
  CACHE_ASYNC_STORE=1
  template_hash_suffix=""

  HYPR_WAL_CACHE_ENABLE="${HYPR_WAL_CACHE_ENABLE:-1}"
  HYPR_WAL_CACHE_DIR="${HYPR_WAL_CACHE_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wal/cache}"
  WAL_CACHE_PRUNE_ENABLED="${HYPR_WAL_CACHE_PRUNE:-1}"
  WAL_CACHE_PRUNE_TTL="${HYPR_WAL_CACHE_PRUNE_TTL:-21600}"
  WAL_CACHE_PRUNE_STAMP="${HYPR_WAL_CACHE_DIR}/.prune.ts"

  case "${WAL_CACHE_PRUNE_ENABLED,,}" in
    1 | true | yes | on) WAL_CACHE_PRUNE_ENABLED=1 ;;
    0 | false | no | off) WAL_CACHE_PRUNE_ENABLED=0 ;;
    *) WAL_CACHE_PRUNE_ENABLED=1 ;;
  esac

  [[ "${WAL_CACHE_PRUNE_TTL}" =~ ^[0-9]+$ ]] || WAL_CACHE_PRUNE_TTL=21600

  wal_cache_key=""
  wal_cache_path=""
  wal_cache_populate=0
  wal_used_cache=0
  wal_output=""
  wal_exit=""
}

color_plan_prepare_cache_strategy() {
  local prev_key=""
  local previous_mode=""
  local allow_fast_path=0

  [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]] || return 0

  mkdir -p "${HYPR_WAL_CACHE_DIR}" 2>/dev/null || true
  wall_hash="$(${HYPR_HASH_COMMAND:-sha1sum} "${WALLPAPER_IMAGE}" | awk '{print $1}')"
  compute_template_hash
  legibility_suffix="$(compute_legibility_suffix)"
  wal_cache_key="${wall_hash}_${resolved_color_variant}_${PYWAL_BACKEND}${legibility_suffix}${template_hash_suffix}"
  wal_cache_path="${HYPR_WAL_CACHE_DIR}/${wal_cache_key}"
  wal_cache_backend="${PYWAL_BACKEND}"

  queue_cache_cleanup "${HYPR_WAL_CACHE_DIR}" "${template_hash_suffix}"
  queue_wal_cache_prune
  color_state_read_cache_metadata prev_key previous_mode

  if [[ "${FORCE_COLOR_REGEN:-0}" -ne 1 ]] && [[ "${selected_color_mode}" -ne 0 ]]; then
    [[ "${previous_mode}" =~ ^[0-9]+$ ]] && [[ "${previous_mode}" -ne 0 ]] && allow_fast_path=1
  fi

  if [[ "${prev_key}" == "${wal_cache_key}" ]]; then
    if [[ "${allow_fast_path}" -eq 1 ]]; then
      print_log -sec "pywal16" -stat "cache" "current (fast-path)"
      color_state_persist
      exit 0
    fi
    wal_used_cache=1
    wal_exit=0
    print_log -sec "pywal16" -stat "cache" "current"
    return 0
  fi

  if wal_cache_valid "${wal_cache_path}"; then
    print_log -sec "pywal16" -stat "cache" "hit"
    if wal_cache_swap_dir "${wal_cache_path}" "${WAL_CACHE}"; then
      wal_used_cache=1
      wal_exit=0
    else
      print_log -sec "pywal16" -warn "cache" "restore failed, regenerating"
      wal_exit=""
    fi
  fi
}

color_plan_refresh_cache_key_for_backend_change() {
  if [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]] && [[ -n "${wall_hash:-}" ]] && [[ "${wal_cache_backend:-}" != "${PYWAL_BACKEND}" ]]; then
    wal_cache_key="${wall_hash}_${resolved_color_variant}_${PYWAL_BACKEND}${legibility_suffix}${template_hash_suffix}"
    wal_cache_path="${HYPR_WAL_CACHE_DIR}/${wal_cache_key}"
  fi
}
