#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Shared selection helpers for screenshot tooling.

capture_start_freeze() {
  local delay="${1:-0.1}"
  local freeze_pid=""

  if command -v hyprpicker >/dev/null 2>&1; then
    hyprpicker -r -z >/dev/null 2>&1 &
    freeze_pid=$!
    sleep "${delay}"
  fi

  printf '%s\n' "${freeze_pid}"
}

capture_stop_freeze() {
  local freeze_pid="${1:-}"
  [[ -n "${freeze_pid}" ]] && kill "${freeze_pid}" 2>/dev/null || true
}

capture_monitor_geometry_jq() {
  cat <<'EOF'
def format_geo:
  .x as $x | .y as $y |
  (.width / .scale | floor) as $w |
  (.height / .scale | floor) as $h |
  .transform as $t |
  if $t == 1 or $t == 3 then
    "\($x),\($y) \($h)x\($w)"
  else
    "\($x),\($y) \($w)x\($h)"
  end;
EOF
}

capture_active_workspace_rectangles() {
  local geometry_filter
  geometry_filter="$(capture_monitor_geometry_jq)"

  hyprctl --batch -j "monitors;clients" \
    | jq -sr "${geometry_filter}
        .[0] as \$monitors
        | (.[1] // []) as \$clients
        | (\$monitors[] | select(.focused == true) | .activeWorkspace.id) as \$active_workspace
        | (\$monitors[] | select(.activeWorkspace.id == \$active_workspace) | format_geo),
          (\$clients[] | select(.workspace.id == \$active_workspace) | \"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])\")
      "
}

capture_visible_workspace_rectangles() {
  local geometry_filter
  geometry_filter="$(capture_monitor_geometry_jq)"

  hyprctl --batch -j "monitors;workspaces;clients" \
    | jq -sr "${geometry_filter}
        .[0] as \$monitors
        | (.[1] // []) as \$workspace_data
        | (.[2] // []) as \$clients
        | (\$workspace_data | map(select(.hasfullscreen) | .id)) as \$fullscreen_workspaces
        | (\$monitors | map((if .specialWorkspace.name == \"\" then .activeWorkspace else .specialWorkspace end).id)) as \$workspaces
        | (\$monitors[] | format_geo),
          (
            \$clients
            | map(select(
                ([.workspace.id] | inside(\$workspaces))
                and (([.workspace.id] | inside(\$fullscreen_workspaces) | not) or .fullscreen > 0)
              ))
            | .[]
            | \"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])\"
          )
      "
}
