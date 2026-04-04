#!/usr/bin/env bash

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
  local mon_data active_workspace geometry_filter
  geometry_filter="$(capture_monitor_geometry_jq)"
  mon_data="$(hyprctl monitors -j)"
  active_workspace="$(jq -r '.[] | select(.focused == true) | .activeWorkspace.id' <<<"${mon_data}")"

  jq -r --arg ws "${active_workspace}" "${geometry_filter} .[] | select(.activeWorkspace.id == (\$ws | tonumber)) | format_geo" <<<"${mon_data}"
  hyprctl clients -j | jq -r --arg ws "${active_workspace}" '.[] | select(.workspace.id == ($ws | tonumber)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

capture_visible_workspace_rectangles() {
  local mon_data workspaces fullscreen_workspaces geometry_filter
  geometry_filter="$(capture_monitor_geometry_jq)"
  mon_data="$(hyprctl monitors -j)"
  fullscreen_workspaces="$(hyprctl workspaces -j | jq -r 'map(select(.hasfullscreen) | .id)')"
  workspaces="$(jq -r '[(foreach .[] as $monitor (0; if $monitor.specialWorkspace.name == "" then $monitor.activeWorkspace else $monitor.specialWorkspace end)).id]' <<<"${mon_data}")"

  jq -r "${geometry_filter} .[] | format_geo" <<<"${mon_data}"
  hyprctl clients -j | jq -r \
    --argjson workspaces "${workspaces}" \
    --argjson fullscreenWorkspaces "${fullscreen_workspaces}" \
    'map(select(([.workspace.id] | inside($workspaces)) and (([.workspace.id] | inside($fullscreenWorkspaces) | not) or .fullscreen > 0))) | .[] | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}
