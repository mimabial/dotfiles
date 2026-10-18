WINDOWS_WORKFLOW_THEME="Windows 11"

workflow_theme_state() {
  jq -cn --arg theme "$(state_get HYPR_THEME)" \
    --arg source "$(state_get selected_color_source theme)" \
    --arg mode "$(state_get selected_color_mode "${STATE_COLOR_MODE_DARK}")" \
    '{theme: $theme, source: $source, mode: $mode}'
}

windows_capture() {
  hyprctl -j --batch 'getoption general:layout ; clients' | jq -sc \
    --arg theme "$(state_get HYPR_THEME)" \
    --arg source "$(state_get selected_color_source theme)" \
    --arg mode "$(state_get selected_color_mode "${STATE_COLOR_MODE_DARK}")" \
    --arg workflow "${workflow_previous_name}" \
    '{theme: $theme, source: $source, mode: $mode, workflow: $workflow, layout: .[0].str,
      windows: [.[1][] | select(.workspace.id > 0 and (.pinned | not) and (.hidden | not) and .fullscreen == 0)
        | {address, floating, at, size}]}'
}

windows_enter() {
  local previous
  [[ "${workflow_previous_name}" == gaming && -n "$(state_get WORKFLOW_WINDOWS_PREVIOUS)" ]] && return
  previous="$(windows_capture)" || return 1
  state_set WORKFLOW_WINDOWS_PREVIOUS "${previous}" staterc || return 1
  state_set selected_color_source theme staterc || return 1
  if "${HYPR_LIB_DIR}/theme/theme.switch.sh" --set "${WINDOWS_WORKFLOW_THEME}" --quiet; then
    state_set WORKFLOW_WINDOWS_PREVIOUS "$(jq -c --argjson applied "$(workflow_theme_state)" '.applied = $applied' <<<"${previous}")" staterc
    return
  fi
  state_set selected_color_source "$(jq -r '.source' <<<"${previous}")" staterc
  state_set selected_color_mode "$(jq -r '.mode' <<<"${previous}")" staterc
  state_set WORKFLOW_WINDOWS_PREVIOUS "" staterc
  return 1
}

windows_restore() {
  local previous current layout mode windows floating result
  previous="$(state_get WORKFLOW_WINDOWS_PREVIOUS)"
  [[ -n "${previous}" ]] || return 0
  current="$(workflow_theme_state)"
  if [[ "${active_workflow_name:-default}" != gaming && "${workflow_previous_theme_override:-}" != 1 ]] && jq -e --argjson current "${current}" '.applied == $current' <<<"${previous}" >/dev/null; then
    mode="$(jq -r '.mode' <<<"${previous}")"
    state_set selected_color_source "$(jq -r '.source' <<<"${previous}")" staterc || return 1
    state_set selected_color_mode "${mode}" staterc || return 1
    if ! "${HYPR_LIB_DIR}/theme/theme.switch.sh" --set "$(jq -r '.theme' <<<"${previous}")" --quiet; then
      state_set selected_color_source "$(jq -r '.source' <<<"${current}")" staterc
      state_set selected_color_mode "$(jq -r '.mode' <<<"${current}")" staterc
      return 1
    fi
    state_set selected_color_mode "${mode}" staterc || return 1
    if [[ "${mode}" == "${STATE_COLOR_MODE_AUTO}" ]]; then hypr_svc_user start auto-theme || return 1; fi
  fi
  windows="{}"
  if [[ "${workflow_previous_layout_changed:-}" != 1 ]]; then
    layout="$(jq -r '.layout' <<<"${previous}")"
    if [[ -z "$(state_get WORKFLOW_WINDOW_LAYOUT)" && "$(hyprctl -j getoption general:layout | jq -r '.str')" != "${layout}" ]]; then
      "${HYPR_LIB_DIR}/util/window-layout.sh" --set "${layout}" || return 1
    fi
    windows="$(jq -r '.windows | map("[" + (.address | @json) + "]={floating=" + (.floating | tostring)
      + ",x=" + (.at[0] | tostring) + ",y=" + (.at[1] | tostring)
      + ",width=" + (.size[0] | tostring) + ",height=" + (.size[1] | tostring) + "}") | "{" + join(",") + "}"' <<<"${previous}")" || return 1
  fi
  [[ "${active_workflow_name:-default}" == floating ]] && floating=true || floating=false
  result="$(hyprctl repl "require(\"floating_windows\").restore(${windows}, ${floating})")" || return 1
  [[ "${result}" == ok ]] || { printf '%s\n' "${result}" >&2; return 1; }
  [[ "${active_workflow_name:-default}" == gaming ]] || state_set WORKFLOW_WINDOWS_PREVIOUS "" staterc
}
