#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state system || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/theme/pairs.sh"
export_hypr_config

hypr_help_guard "Usage: hyprshell theme/color-mode [-q] [n|p|--set <theme|pywal> [dark|light|auto]]
Choose a palette source and colour mode: next (n), prev (p), or explicit --set (default: next)." "$@"

color_mode_values=("${STATE_COLOR_MODE_DARK}" "${STATE_COLOR_MODE_LIGHT}" "${STATE_COLOR_MODE_AUTO}")
MODE_SWITCH_LOCK_FD=""
color_mode_notify=1
selected_color_mode="$(state_get selected_color_mode)"
selected_color_source="$(state_resolve_color_source "$(state_get selected_color_source)" "${selected_color_mode}")"
selected_color_mode="$(state_resolve_color_mode "${selected_color_mode}" "${BACKGROUND_MODE:-}")"

acquire_mode_switch_lock() {
  MODE_SWITCH_LOCK="$(hypr_lock_path mode_switch)"
  exec {MODE_SWITCH_LOCK_FD}>"${MODE_SWITCH_LOCK}"
  ! flock -n "${MODE_SWITCH_LOCK_FD}" && {
    print_log -sec "color-mode" -stat "wait" "Another mode operation in progress, waiting..."
    flock "${MODE_SWITCH_LOCK_FD}"
  }
  trap 'color_mode_release_lock "$?"' EXIT
}

color_mode_release_lock() {
  local exit_code="${1:-$?}"
  if [[ -n "${MODE_SWITCH_LOCK_FD}" ]]; then
    flock -u "${MODE_SWITCH_LOCK_FD}" 2>/dev/null || true
    exec {MODE_SWITCH_LOCK_FD}>&-
    MODE_SWITCH_LOCK_FD=""
  fi
  return "${exit_code}"
}

cycle_color_mode() {
  local i=""
  for i in "${!color_mode_values[@]}"; do
    if [[ "${selected_color_mode}" == "${color_mode_values[i]}" ]]; then
      if [ "${1}" == "n" ]; then
        target_color_mode="${color_mode_values[$(((i + 1) % ${#color_mode_values[@]}))]}"
      elif [ "${1}" == "p" ]; then
        target_color_mode="${color_mode_values[$(((i - 1 + ${#color_mode_values[@]}) % ${#color_mode_values[@]}))]}"
      fi
      break
    fi
  done
}

set_color_mode_from_arg() {
  local mode_arg="$1"

  case "${mode_arg,,}" in
    "${STATE_COLOR_MODE_AUTO}" | auto) target_color_mode="${STATE_COLOR_MODE_AUTO}" ;;
    "${STATE_COLOR_MODE_DARK}" | dark) target_color_mode="${STATE_COLOR_MODE_DARK}" ;;
    "${STATE_COLOR_MODE_LIGHT}" | light) target_color_mode="${STATE_COLOR_MODE_LIGHT}" ;;
    *) return 1 ;;
  esac
}

set_policy_from_args() {
  local policy_arg="${1:-}"
  local mode_arg="${2:-}"

  if [[ -z "${policy_arg}" ]]; then
    echo "Error: --set requires theme, pywal, dark, light, or auto"
    exit 1
  fi

  case "${policy_arg,,}" in
    theme | pywal)
      target_color_source="${policy_arg,,}"
      if [[ -n "${mode_arg}" ]] && ! set_color_mode_from_arg "${mode_arg}"; then
        echo "Error: invalid mode: ${mode_arg}"
        echo "Valid modes: dark, light, auto (or 1-3)"
        exit 1
      fi
      ;;
    0)
      target_color_source="theme"
      ;;
    1 | 2 | 3 | auto | dark | light)
      set_color_mode_from_arg "${policy_arg}"
      ;;
    *)
      echo "Error: invalid color policy: ${policy_arg}"
      echo "Valid sources: theme, pywal; valid modes: dark, light, auto"
      exit 1
      ;;
  esac
}

auto_theme_supervised() {
  [[ "$(hypr_init_system)" != "other" ]]
}

start_auto_theme_service() {
  if ! auto_theme_supervised; then
    print_log -sec "color-mode" -warn "auto" "no service manager (systemd/runit) for auto-theme"
    return 1
  fi

  hypr_svc_user start auto-theme || {
    print_log -sec "color-mode" -warn "auto" "failed to start auto-theme service"
    return 1
  }
}

refresh_auto_theme_service() {
  auto_theme_supervised || return 0
  hypr_svc_user_signal auto-theme USR2 || true
}

stop_auto_theme_service() {
  if auto_theme_supervised; then
    hypr_svc_user stop auto-theme || true
  fi
}

resolve_wallpaper() {
  local wall=""
  for wall in "${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.set" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${HYPR_THEME}/wall.set"; do
    realpath -e "${wall}" 2>/dev/null && return
  done
  print_log -sec "color-mode" -err "wallpaper" "no wall.set for ${HYPR_THEME}"
  return 1
}

apply_color_policy() {
  local wallpaper=""
  local target_mode="dark"
  local hypr_theme_cmd=""
  local target_polarity=""
  local target_theme=""
  local -a theme_switch_cmd=()

  hypr_theme_cmd="$(command -v hypr-theme || true)"
  [[ -n "${hypr_theme_cmd}" ]] || {
    print_log -sec "color-mode" -err "hypr-theme" "command not found"
    return 1
  }

  case "${target_color_mode}" in
    "${STATE_COLOR_MODE_DARK}") target_polarity="dark" ;;
    "${STATE_COLOR_MODE_LIGHT}") target_polarity="light" ;;
  esac

  if [[ -n "${target_polarity}" && "$(theme_polarity "${HYPR_THEME}")" != "${target_polarity}" ]]; then
    target_theme="$(theme_pair_for "${HYPR_THEME}" "${target_polarity}")" || true
    if [[ -n "${target_theme}" && "${target_theme}" != "${HYPR_THEME}" ]]; then
      theme_switch_cmd=("${LIB_DIR}/hypr/theme/theme.switch.sh" -s "${target_theme}")
      [[ "${color_mode_notify}" -eq 0 ]] && theme_switch_cmd+=(--quiet)
      "${theme_switch_cmd[@]}"
      return $?
    fi
  fi

  case "${target_color_mode}" in
    "${STATE_COLOR_MODE_DARK}") target_mode="dark" ;;
    "${STATE_COLOR_MODE_LIGHT}") target_mode="light" ;;
    *)
      target_mode="$(state_get_color_variant 2>/dev/null || true)"
      [[ "${target_mode}" =~ ^(dark|light)$ ]] || target_mode="${BACKGROUND_MODE:-}"
      [[ "${target_mode}" =~ ^(dark|light)$ ]] || target_mode="dark"
      ;;
  esac

  if [[ "${target_color_source}" == "theme" ]]; then
    "${hypr_theme_cmd}" apply "${HYPR_THEME}"
    return $?
  fi

  wallpaper="$(resolve_wallpaper)" || return 1
  state_set "BACKGROUND_MODE" "${target_mode}" "staterc"
  state_set_color_variant "${target_mode}"

  "${hypr_theme_cmd}" wallpaper --variant "${target_mode}" "${wallpaper}"
}

parse_target_policy() {
  target_color_source="${selected_color_source}"
  target_color_mode="${selected_color_mode}"

  case "${1:-}" in
    n | -n | --next) cycle_color_mode n ;;
    p | -p | --prev) cycle_color_mode p ;;
    -s | --set) set_policy_from_args "${2:-}" "${3:-}" ;;
    --set=*) set_policy_from_args "${1#--set=}" "${2:-}" ;;
    *) cycle_color_mode n ;;
  esac

  if [[ ! "${target_color_source}" =~ ^(theme|pywal)$ ]] || ! state_color_mode_is_valid "${target_color_mode}"; then
    echo "Error: invalid target color policy: ${target_color_source}/${target_color_mode}"
    exit 1
  fi
}

load_previous_color_policy() {
  previous_color_source="${selected_color_source}"
  previous_color_mode="${selected_color_mode}"
}

persist_color_policy() {
  state_set "selected_color_source" "${target_color_source}" "staterc"
  state_set "selected_color_mode" "${target_color_mode}" "staterc"
}

notify_color_mode_changed() {
  local -A mode_labels=(["${STATE_COLOR_MODE_AUTO}"]=Auto ["${STATE_COLOR_MODE_DARK}"]=Dark ["${STATE_COLOR_MODE_LIGHT}"]=Light)
  [[ "${color_mode_notify}" -eq 1 ]] || return 0
  send_ephemeral_notif color-mode -a "Color mode" -t 2000 -i preferences-desktop-theme \
    "Color mode" "${target_color_source^} · ${mode_labels[${target_color_mode}]}" || true
}

revert_failed_auto_mode() {
  print_log -sec "color-mode" -warn "auto" "activation failed, reverting mode"
  target_color_source="${previous_color_source}"
  target_color_mode="${previous_color_mode}"
  persist_color_policy
  if [[ "${target_color_mode}" != "${STATE_COLOR_MODE_AUTO}" ]]; then
    stop_auto_theme_service
    apply_color_policy || exit 1
  fi
  exit 1
}

apply_auto_mode() {
  persist_color_policy
  start_auto_theme_service || revert_failed_auto_mode
  refresh_auto_theme_service
}

apply_manual_mode() {
  stop_auto_theme_service
  persist_color_policy
  if ! apply_color_policy; then
    target_color_source="${previous_color_source}"
    target_color_mode="${previous_color_mode}"
    persist_color_policy
    if [[ "${previous_color_mode}" == "${STATE_COLOR_MODE_AUTO}" ]]; then
      start_auto_theme_service || true
      refresh_auto_theme_service
    fi
    exit 1
  fi
}

main() {
  acquire_mode_switch_lock
  if [[ "${1:-}" == "-q" || "${1:-}" == "--quiet" ]]; then
    color_mode_notify=0
    shift
  fi
  parse_target_policy "$@"
  load_previous_color_policy

  if [[ "${target_color_mode}" == "${STATE_COLOR_MODE_AUTO}" ]]; then
    apply_auto_mode
  else
    apply_manual_mode
  fi

  notify_color_mode_changed
}

main "$@"
