workflow_locked() {
  local owner=""
  [[ "${HYPR_WORKFLOW_UNLOCK:-0}" == 1 ]] && return 1
  hypr_gamemode_active && owner=gaming
  [[ -z "${owner}" && "${HYPR_PROFILE_WORKFLOW_LOCK:-1}" != 0 && "$(hypr_power_profile)" == power-saver ]] && owner=powersaver
  [[ -n "${owner}" && "${1:-}" != "${owner}" ]]
}

workflow_resolve_path() {
  local name="${1:-default}"
  name="${name%.lua}"
  hypr_visual_preset_resolve_path "${name}" "lua" "${workflows_user_dir}" "${workflows_shared_dir}"
}

workflow_exists() {
  local name="${1:-}"
  [[ -n "${name}" ]] || return 1
  workflow_resolve_path "${name}" >/dev/null 2>&1
}

workflow_list_names() {
  hypr_visual_preset_list_names "lua" "${workflows_user_dir}" "${workflows_shared_dir}"
}

workflow_read_icon() {
  local workflow_path="$1"
  local workflow_icon
  workflow_icon="$(sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_ICON",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1)"
  printf '%s\n' "${workflow_icon:0:1}"
}

workflow_read_description() {
  local workflow_path="$1"
  local description
  description="$(sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_DESCRIPTION",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1)"
  printf '%s\n' "${description:-No description available}"
}

workflow_read_bar_layouts() {
  local workflow_path="$1"
  sed -n 's/^[[:space:]]*vars\.set("WORKFLOW_QUICKSHELL_LAYOUT",[[:space:]]*"\([^"]*\)").*/\1/p' "${workflow_path}" | head -n1
}

workflow_list_choices() {
  local name path
  while IFS= read -r name; do
    [[ "${name}" =~ ^(gaming|powersaver)$ ]] && continue
    path="$(workflow_resolve_path "${name}")" || continue
    printf '%s\t%s\t%s\n' "${name}" "$(workflow_read_icon "${path}")" "$(workflow_read_description "${path}")"
  done < <(workflow_list_names)
}

workflow_load_active() {
  local workflow_path

  active_workflow_name="$(state_get "HYPR_WORKFLOW" "default")"

  workflow_path="$(workflow_resolve_path "${active_workflow_name}" || true)"
  if [[ -z "${workflow_path}" ]]; then
    active_workflow_name=default
    workflow_path="$(workflow_resolve_path default)"
  fi

  active_workflow_icon="$(workflow_read_icon "${workflow_path}")"
  active_workflow_description="$(workflow_read_description "${workflow_path}")"
  active_workflow_path="${workflow_path}"
}

workflow_emit_bar_status() {
  workflow_load_active
  printf '{"text": "%s", "class": "custom-workflows"}\n' "${active_workflow_icon}"
}
workflows_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/workflows"
workflows_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/workflows"
workflows_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/workflows.lua"


workflow_write_config() {
  hypr_visual_preset_write_lua "${workflows_state_file}" \
    --load "${active_workflow_path}" \
    "WORKFLOW=${active_workflow_name}" \
    "WORKFLOW_ICON=${active_workflow_icon}" \
    "WORKFLOW_DESCRIPTION=${active_workflow_description}" \
    "WORKFLOW_PATH=${active_workflow_path}" \
    "WORKFLOW_LAYOUT_OVERRIDE=$(state_get WORKFLOW_LAYOUT_OVERRIDE)"
}
