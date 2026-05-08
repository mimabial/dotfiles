#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# color.plan.sh - Resolve theme/wallpaper/variant context for a color-sync run
# and compute the cache key. Owns the contract between selected_color_mode,
# resolved_color_variant, and the wal cache fast-path.

# Color-mode state contract:
#   selected_color_mode: persistent requested policy shared across the wal/theme
#     pipeline and stored in staterc.
#       0 = theme mode   (use the theme palette instead of wallpaper-derived wal)
#       1 = auto mode    (reuse the last persisted concrete variant)
#       2 = force dark   (always resolve to dark)
#       3 = force light  (always resolve to light)
#   resolved_color_variant: concrete dark|light variant for the current run.
#     Even in theme mode, downstream desktop sync still needs a concrete variant
#     for things like COLOR_SCHEME, cache keys, and opposite-mode precache.
#   MODE_OVERRIDE: transient per-run dark|light override from
#     HYPR_WAL_MODE_OVERRIDE. This changes only the concrete variant for the
#     current execution and does not rewrite selected_color_mode.
# Resolution order:
#   MODE_OVERRIDE > fixed mode (2/3) > persisted auto variant (mode 1) > dark

color_plan_init_mode_state() {
  selected_color_mode="${selected_color_mode:-1}"
  resolved_color_variant="${resolved_color_variant:-dark}"
  SKIP_WAYBAR_UPDATE="${SKIP_WAYBAR_UPDATE:-0}"

  case "${selected_color_mode}" in
    0 | 1 | 2 | 3) ;;
    *)
      print_log -sec "pywal16" -warn "mode" "invalid selected_color_mode: ${selected_color_mode}, defaulting to auto"
      selected_color_mode=1
      ;;
  esac
}

color_plan_load_auto_variant_state() {
  local persisted_variant=""

  [[ -z "${MODE_OVERRIDE}" ]] || return 0
  [[ "${selected_color_mode}" == "1" ]] || return 0
  [[ -f "${HYPR_STATE_HOME}/color_variant" ]] || return 0

  persisted_variant="$(<"${HYPR_STATE_HOME}/color_variant")"
  case "${persisted_variant}" in
    dark | light) resolved_color_variant="${persisted_variant}" ;;
    *)
      print_log -sec "pywal16" -warn "mode" "invalid persisted color_variant: ${persisted_variant}"
      ;;
  esac
}

color_plan_apply_variant_overrides() {
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
}

color_plan_resolve_theme_context() {
  color_plan_init_mode_state
  color_plan_load_auto_variant_state

  if [[ -z "${HYPR_THEME:-}" ]]; then
    print_log -sec "theme" -err "state" "HYPR_THEME is not set"
    return 1
  fi

  HYPR_THEME_DIR="${HYPR_THEME_DIR:-${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}}"
  if [[ ! -d "${HYPR_THEME_DIR}" ]]; then
    print_log -sec "theme" -err "state" "theme not found: ${HYPR_THEME}"
    return 1
  fi
  export HYPR_THEME HYPR_THEME_DIR

  color_plan_apply_variant_overrides
  return 0
}

color_plan_prepare_wal_cache_root() {
  WAL_XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

  if [[ "${CACHE_ONLY}" -eq 1 ]]; then
    local cache_only_root_base=""
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && [[ -d "${XDG_RUNTIME_DIR}" ]]; then
      cache_only_root_base="${XDG_RUNTIME_DIR}/hypr"
    else
      cache_only_root_base="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
    fi
    mkdir -p "${cache_only_root_base}" || {
      print_log -sec "pywal16" -err "cache" "failed to create ${cache_only_root_base}"
      return 1
    }
    CACHE_ONLY_ROOT="$(mktemp -d -p "${cache_only_root_base}" "wal-cache-only.XXXXXXXX")" || {
      print_log -sec "pywal16" -err "cache" "temp dir failed"
      return 1
    }
    WAL_XDG_CACHE_HOME="${CACHE_ONLY_ROOT}"
  fi

  WAL_CACHE="${WAL_XDG_CACHE_HOME}/wal"
  mkdir -p "${WAL_CACHE}" || {
    print_log -sec "pywal16" -err "cache" "failed to create ${WAL_CACHE}"
    return 1
  }
  return 0
}

color_plan_init_cache_controls() {
  template_hash_suffix=""

  HYPR_WAL_CACHE_ENABLE="${HYPR_WAL_CACHE_ENABLE:-1}"
  HYPR_WAL_CACHE_DIR="${HYPR_WAL_CACHE_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wal/cache}"
  WAL_CACHE_PRUNE_ENABLED="${HYPR_WAL_CACHE_PRUNE:-1}"
  WAL_CACHE_PRUNE_TTL="${HYPR_WAL_CACHE_PRUNE_TTL:-21600}"

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
  color_plan_fast_path_current=0
  wal_output=""
  wal_exit=""
}

color_plan_prepare_cache_strategy() {
  local prev_key=""
  local previous_mode=""
  local allow_fast_path=0
  local theme_input_hash=""

  [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]] || return 0

  if ! mkdir -p "${HYPR_WAL_CACHE_DIR}" 2>/dev/null; then
    print_log -sec "pywal16" -warn "cache" "failed to access ${HYPR_WAL_CACHE_DIR}; disabling cache"
    HYPR_WAL_CACHE_ENABLE=0
    return 0
  fi

  compute_template_hash

  if [[ "${PALETTE_SOURCE}" == "theme" ]]; then
    theme_input_hash="$(compute_theme_mode_input_hash)" || {
      print_log -sec "pywal16" -warn "cache" "theme input hash failed; disabling cache"
      HYPR_WAL_CACHE_ENABLE=0
      return 0
    }
    wal_cache_key="theme_${theme_input_hash}_${resolved_color_variant}_${PYWAL_BACKEND}${template_hash_suffix}"
  else
    wall_hash="$(${HYPR_HASH_COMMAND:-sha1sum} "${WALLPAPER_IMAGE}" | awk '{print $1}')"
    legibility_suffix="$(compute_legibility_suffix)"
    wal_cache_key="${wall_hash}_${resolved_color_variant}_${PYWAL_BACKEND}${legibility_suffix}${template_hash_suffix}"
  fi

  wal_cache_path="${HYPR_WAL_CACHE_DIR}/${wal_cache_key}"
  wal_cache_backend="${PYWAL_BACKEND}"

  cache_cleanup_stale "${HYPR_WAL_CACHE_DIR}" "${template_hash_suffix}" >/dev/null 2>&1 &
  color_state_read_cache_metadata prev_key previous_mode

  if [[ "${FORCE_COLOR_REGEN:-0}" -eq 1 ]]; then
    print_log -sec "pywal16" -stat "cache" "bypass (--regen)"
    return 0
  fi

  if [[ "${FORCE_COLOR_REGEN:-0}" -ne 1 ]] && [[ "${selected_color_mode}" -ne 0 ]]; then
    [[ "${previous_mode}" =~ ^[0-9]+$ ]] && [[ "${previous_mode}" -ne 0 ]] && allow_fast_path=1
  elif [[ "${FORCE_COLOR_REGEN:-0}" -ne 1 ]] && [[ "${selected_color_mode}" -eq 0 ]]; then
    [[ "${previous_mode}" =~ ^[0-9]+$ ]] && [[ "${previous_mode}" -eq 0 ]] && allow_fast_path=1
  fi

  if [[ "${prev_key}" == "${wal_cache_key}" ]]; then
    if [[ "${allow_fast_path}" -eq 1 ]]; then
      print_log -sec "pywal16" -stat "cache" "current (fast-path)"
      color_state_persist
      color_plan_fast_path_current=1
      return 0
    fi
    wal_used_cache=1
    wal_exit=0
    print_log -sec "pywal16" -stat "cache" "current"
    return 0
  fi

  if wal_cache_valid "${wal_cache_path}"; then
    print_log -sec "pywal16" -stat "cache" "hit"
    if wal_cache_restore "${wal_cache_path}" "${WAL_CACHE}"; then
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
