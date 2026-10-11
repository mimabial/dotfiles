workflow_bar_edge() {
  PYTHONPATH="${HYPR_LIB_DIR}" python3 -c 'from pyutils.bar_edge import bar_edge; print(bar_edge())'
}

workflow_bar_layout_for_edge() {
  PYTHONPATH="${HYPR_LIB_DIR}" python3 - "$@" <<'PY'
import sys
from pyutils.bar_edge import bar_edge
edge = bar_edge()
print(next((layout for layout in sys.argv[1:] if bar_edge(layout) == edge), sys.argv[1]))
PY
}

workflow_apply_bar_layout() {
  local current_layout_name saved_layout target_layout=""
  local last_applied allowed

  read -ra allowed <<<"$(workflow_read_bar_layouts "${active_workflow_path}")"
  current_layout_name="$(state_get "QUICKSHELL_LAYOUT_NAME" "top")"
  saved_layout="$(state_get "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "")"
  last_applied="$(state_get "WORKFLOW_QUICKSHELL_LAST_APPLIED_LAYOUT" "")"

  if ((${#allowed[@]})); then
    if [[ "${workflow_previous_name}" != "${active_workflow_name}" && " ${allowed[*]} " != *" ${current_layout_name} "* ]]; then
      target_layout="$(workflow_bar_layout_for_edge "${allowed[@]}")"
      [[ -z "${saved_layout}" ]] && state_set "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "${current_layout_name}" "staterc"
    fi
  elif [[ -n "${saved_layout}" ]]; then
    state_set "WORKFLOW_QUICKSHELL_PREV_LAYOUT" "" "staterc"
    if [[ -z "${last_applied}" || "${current_layout_name}" == "${last_applied}" ]]; then
      target_layout="$(workflow_bar_layout_for_edge "${saved_layout}" top bottom)"
      [[ "${target_layout}" == "${current_layout_name}" ]] && target_layout=""
    fi
  fi

  [[ -n "${target_layout}" ]] || return 0
  if [[ "${target_layout}" == winbar ]]; then
    quickshell ipc call bar winbarEdge "$(workflow_bar_edge)" >/dev/null 2>&1 || true
  fi
  state_set "WORKFLOW_QUICKSHELL_LAST_APPLIED_LAYOUT" "${target_layout}" "staterc"
  state_set "QUICKSHELL_LAYOUT_NAME" "${target_layout}" "staterc"
  hyprshell render/dunst.py >/dev/null 2>&1 || true
}
