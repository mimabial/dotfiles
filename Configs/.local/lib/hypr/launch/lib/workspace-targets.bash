launch_workspace_has_other_window() {
  local workspace_name="$1"
  local exclude_address="$2"
  local clients_json="$3"

  jq -r --arg workspace "${workspace_name}" --arg exclude "${exclude_address}" \
    'any(.[]; .workspace.name == $workspace and .address != $exclude)' <<<"${clients_json}"
}

launch_focus_empty_workspace() {
  launch_source_core_common || return 1
  hypr_lua_dispatch 'hl.dsp.focus({workspace="empty"})' >/dev/null 2>&1 || return 1
  hyprctl activeworkspace -j | jq -r '.name // empty'
}
