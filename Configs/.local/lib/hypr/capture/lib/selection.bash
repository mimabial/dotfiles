#!/usr/bin/env bash

declare -F hypr_ensure_runtime_dir_into >/dev/null || source "${BASH_SOURCE[0]%/*}/../../core/common.bash"
declare -F hypr_wait_for >/dev/null || source "${BASH_SOURCE[0]%/*}/../../core/events.bash"
declare -F notify_send_safe >/dev/null || source "${BASH_SOURCE[0]%/*}/../../core/notify.bash"

CAPTURE_CLICK_MAX_AREA_PIXELS=20

capture_start_freeze() {
  local freeze_pid=""

  if command -v hyprpicker >/dev/null 2>&1; then
    hyprpicker -r -z >/dev/null 2>&1 &
    freeze_pid=$!
    hypr_wait_for 1 'openlayer>>hyprpicker' hypr_layer_mapped hyprpicker \
      || { kill "${freeze_pid}" 2>/dev/null || true; freeze_pid=""; }
  fi

  printf '%s\n' "${freeze_pid}"
}

capture_stop_freeze() {
  local freeze_pid="${1:-}"
  [[ -n "${freeze_pid}" ]] && kill "${freeze_pid}" 2>/dev/null || true
}

CAPTURE_MONITOR_GEOMETRY_JQ='def rotated_sideways: .transform % 2 == 1;
def format_geo:
  .x as $x | .y as $y |
  (.width / .scale | floor) as $w |
  (.height / .scale | floor) as $h |
  if rotated_sideways then
    "\($x),\($y) \($h)x\($w)"
  else
    "\($x),\($y) \($w)x\($h)"
  end;'

capture_active_workspace_rectangles() {
  hyprctl --batch -j "monitors;clients" \
    | jq -sr "${CAPTURE_MONITOR_GEOMETRY_JQ}
        .[0] as \$monitors
        | (.[1] // []) as \$clients
        | (\$monitors[] | select(.focused == true) | .activeWorkspace.id) as \$active_workspace
        | (\$monitors[] | select(.activeWorkspace.id == \$active_workspace) | format_geo),
          (\$clients[] | select(.workspace.id == \$active_workspace) | \"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])\")
      "
}

capture_visible_workspace_rectangles() {
  hyprctl --batch -j "monitors;workspaces;clients" \
    | jq -sr "${CAPTURE_MONITOR_GEOMETRY_JQ}
        .[0] as \$monitors
        | (.[1] // []) as \$workspace_data
        | (.[2] // []) as \$clients
        | (\$workspace_data | map(select(.hasfullscreen) | .name)) as \$fullscreen_workspaces
        | (\$monitors | map((if .specialWorkspace.name == \"\" then .activeWorkspace else .specialWorkspace end).name)) as \$workspaces
        | (\$monitors[] | format_geo),
          (
            \$clients
            | map(select(
                (.workspace.name | IN(\$workspaces[]))
                and ((.workspace.name | IN(\$fullscreen_workspaces[]) | not) or .fullscreen > 0)
              ))
            | .[]
            | \"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])\"
          )
      "
}

capture_select_geometry() {
  local freeze="$1" rectangles="$2"
  shift 2
  local selection="" freeze_pid="" selection_lock_fd="" runtime_dir=""

  hypr_ensure_runtime_dir_into runtime_dir || return 1
  exec {selection_lock_fd}>"${runtime_dir}/capture-selection.lock"
  flock -n "${selection_lock_fd}" || return 1
  [[ "${freeze}" != frozen ]] || freeze_pid="$(capture_start_freeze)"
  selection="$(slurp "$@" 2>/dev/null <<<"${rectangles}")"
  capture_stop_freeze "${freeze_pid}"
  [[ -n "${selection}" ]] || return 1
  printf '%s\n' "${selection}"
}

capture_expand_tiny_selection() {
  local selection="$1"
  local rectangles="$2"
  local rect=""

  if [[ "${selection}" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
    if (( BASH_REMATCH[3] * BASH_REMATCH[4] < CAPTURE_CLICK_MAX_AREA_PIXELS )); then
      local click_x="${BASH_REMATCH[1]}"
      local click_y="${BASH_REMATCH[2]}"

      while IFS= read -r rect; do
        if [[ "$rect" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+) ]]; then
          local rect_x="${BASH_REMATCH[1]}"
          local rect_y="${BASH_REMATCH[2]}"
          local rect_width="${BASH_REMATCH[3]}"
          local rect_height="${BASH_REMATCH[4]}"

          if (( click_x >= rect_x && click_x < rect_x+rect_width && click_y >= rect_y && click_y < rect_y+rect_height )); then
            selection="${rect_x},${rect_y} ${rect_width}x${rect_height}"
            break
          fi
        fi
      done <<<"${rectangles}"
    fi
  fi

  printf '%s\n' "${selection}"
}

capture_smart_select() {
  local rectangles="" selection=""

  rectangles="$(capture_active_workspace_rectangles)"
  selection="$(capture_select_geometry frozen "${rectangles}")" || return 1
  capture_expand_tiny_selection "${selection}" "${rectangles}"
}
