#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

_idle_state_helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! declare -F state_get >/dev/null 2>&1 || ! declare -F state_set >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_idle_state_helper_dir}/../core/state.sh"
fi
if ! declare -F hypr_user_pgrep >/dev/null 2>&1 || ! declare -F hypr_user_pkill >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_idle_state_helper_dir}/../core/common.sh"
fi

if ! declare -F print_log >/dev/null 2>&1; then
  print_log() { :; }
fi

idle_manual_enabled() {
  [[ "$(state_get "HYPR_KEEP_AWAKE" "0")" == "1" ]]
}

idle_audio_enabled() {
  [[ "$(state_get "HYPR_KEEP_AWAKE_AUDIO" "1")" != "0" ]]
}

idle_fullscreen_enabled() {
  [[ "$(state_get "HYPR_KEEP_AWAKE_FULLSCREEN" "0")" == "1" ]]
}

idle_window_activity() {
  command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
  hyprctl --batch -j 'clients;monitors' 2>/dev/null | jq -rse '
    (.[0] // []) as $clients | (.[1] // []) as $monitors |
    def visible($c): any($monitors[]?;
      .activeWorkspace.id == $c.workspace.id
      or ((.specialWorkspace.id // 0) != 0 and .specialWorkspace.id == $c.workspace.id));
    def covers($c): any($monitors[]?;
      .id == $c.monitor
      and (($c.at[0] - .x) | fabs) <= 2 and (($c.at[1] - .y) | fabs) <= 2
      and $c.size[0] >= ((if ((.transform // 0) % 2) == 1 then .height else .width end) / (.scale // 1)) - 2
      and $c.size[1] >= ((if ((.transform // 0) % 2) == 1 then .width else .height end) / (.scale // 1)) - 2);
    [any($monitors[]?; .fullscreenClient != null),
     any($clients[]?; . as $c | $c.mapped == true and ($c.hidden | not)
       and (($c.fullscreen // 0) == 0) and visible($c)
       and ((($c.class // "") | test("^steam_app_[0-9]+$")) or covers($c)))]
    | map(if . then 1 else 0 end) | @tsv'
}

idle_window_state_file() {
  printf '%s/caffeine-windows\n' "$(hypr_runtime_subdir hypr)"
}

idle_set_manual() {
  local value="${1:-0}"
  state_set "HYPR_KEEP_AWAKE" "${value}" "staterc"
}

idle_set_audio() {
  local value="${1:-1}"
  state_set "HYPR_KEEP_AWAKE_AUDIO" "${value}" "staterc"
}

idle_set_fullscreen() {
  local value="${1:-0}"
  state_set "HYPR_KEEP_AWAKE_FULLSCREEN" "${value}" "staterc"
}

idle_notify() {
  if command -v dunstify >/dev/null 2>&1; then
    dunstify "$@"
  fi
}

idle_ensure_manager_running() {
  local manager_unit="${1:-hyprland-idle-manager.service}"

  hypr_svc_user start "${manager_unit}" || true
}

idle_notify_manager() {
  local manager_unit="${1:-hyprland-idle-manager.service}"
  local manager_script="${2:-${HOME}/.local/lib/hypr/session/idle-manager.sh}"

  if hypr_svc_user is-active "${manager_unit}"; then
    hypr_svc_user_signal "${manager_unit}" USR1 || true
    return 0
  fi

  while IFS= read -r pid; do
    kill -USR1 "${pid}" 2>/dev/null || true
  done < <(hypr_user_pgrep -f "${manager_script}" 2>/dev/null || true)
}

idle_toggle_state() {
  local enabled_fn="$1"
  local setter_fn="$2"
  local disabled_value="$3"
  local disabled_icon="$4"
  local disabled_summary="$5"
  local enabled_value="$6"
  local enabled_icon="$7"
  local enabled_summary="$8"
  local disabled_body="${9:-}"
  local enabled_body="${10:-}"
  local manager_unit="${11:-hyprland-idle-manager.service}"
  local manager_script="${12:-${HOME}/.local/lib/hypr/session/idle-manager.sh}"

  local icon summary body
  if "${enabled_fn}"; then
    "${setter_fn}" "${disabled_value}"
    icon="${disabled_icon}" summary="${disabled_summary}" body="${disabled_body}"
  else
    "${setter_fn}" "${enabled_value}"
    icon="${enabled_icon}" summary="${enabled_summary}" body="${enabled_body}"
  fi

  local notify_args=(-t 3000 -i "${icon}" "${summary}")
  [[ -n "${body}" ]] && notify_args+=("${body}")
  idle_notify "${notify_args[@]}"

  idle_ensure_manager_running "${manager_unit}"
  idle_notify_manager "${manager_unit}" "${manager_script}"
}
