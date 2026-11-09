declare -F hypr_dbus_get >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/dbus.bash" || return 1

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

workflow_read_metadata_into() {
  local -n metadata_ref="$1"
  local line="" field=""
  local metadata_pattern='^[[:space:]]*vars\.set\("WORKFLOW_(ICON|DESCRIPTION|QUICKSHELL_LAYOUT)",[[:space:]]*"([^"]*)"\)'

  metadata_ref=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ${metadata_pattern} ]] || continue
    field="${BASH_REMATCH[1]}"
    [[ -n "${metadata_ref[${field}]+set}" ]] || metadata_ref["${field}"]="${BASH_REMATCH[2]}"
  done <"$2"
  metadata_ref[ICON]="${metadata_ref[ICON]:0:1}"
  metadata_ref[DESCRIPTION]="${metadata_ref[DESCRIPTION]:-No description available}"
}

workflow_list_choices() {
  local name path
  local -A metadata=()
  while IFS= read -r name; do
    [[ "${name}" =~ ^(gaming|powersaver)$ ]] && continue
    path="$(workflow_resolve_path "${name}")" || continue
    workflow_read_metadata_into metadata "${path}"
    printf '%s\t%s\t%s\n' "${name}" "${metadata[ICON]}" "${metadata[DESCRIPTION]}"
  done < <(workflow_list_names)
}

workflow_load_active() {
  local workflow_path
  local -A metadata=()

  state_get_into active_workflow_name HYPR_WORKFLOW default

  workflow_path="$(workflow_resolve_path "${active_workflow_name}" || true)"
  if [[ -z "${workflow_path}" ]]; then
    active_workflow_name=default
    workflow_path="$(workflow_resolve_path default)"
  fi

  workflow_read_metadata_into metadata "${workflow_path}"
  active_workflow_icon="${metadata[ICON]}"
  active_workflow_description="${metadata[DESCRIPTION]}"
  active_workflow_bar_layouts="${metadata[QUICKSHELL_LAYOUT]:-}"
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
