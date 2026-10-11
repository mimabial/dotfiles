launch_focused_workspace_name() {
  hyprctl activeworkspace -j | jq -r '.name // empty'
}

launch_active_workspace_occupancy() {
  local exclude_address="${1:-}"
  local snapshot="${2:-}"

  [[ -n "${snapshot}" ]] || snapshot="$(hyprctl --batch -j 'activeworkspace;clients' | jq -sc '.')"
  printf '%s\n' "${snapshot}" \
    | jq -r --arg exclude "${exclude_address}" '
        .[0].name as $workspace_name
        | [
            $workspace_name,
            (
              (.[1] // [])
              | any(.[]; .workspace.name == $workspace_name and .address != $exclude)
            )
          ]
        | @tsv
      '
}

launch_prepare_target_workspace() {
  local use_empty_workspace="$1"
  local exclude_address="${2:-}"
  local snapshot="${3:-}"
  local active_workspace=""
  local has_other_window="false"

  launch_source_core_common || return 1

  if [[ "${use_empty_workspace}" -eq 1 ]]; then
    IFS=$'\t' read -r active_workspace has_other_window \
      < <(launch_active_workspace_occupancy "${exclude_address}" "${snapshot}") || return 1
    [[ -n "${active_workspace}" ]] || return 1

    if [[ "${has_other_window}" == "true" ]]; then
      hypr_lua_dispatch 'hl.dsp.focus({workspace="empty"})' >/dev/null 2>&1 || return 1
      active_workspace="$(launch_focused_workspace_name)"
      [[ -n "${active_workspace}" ]] || return 1
    fi
  else
    if [[ -n "${snapshot}" ]]; then
      active_workspace="$(jq -r '.[0].name // empty' <<<"${snapshot}")"
    else
      active_workspace="$(launch_focused_workspace_name)"
    fi
    [[ -n "${active_workspace}" ]] || return 1
  fi

  printf '%s\n' "${active_workspace}"
}
