#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Shared selection helpers for screenshot tooling.

capture_start_freeze() {
  local freeze_pid="" ready=0

  if command -v hyprpicker >/dev/null 2>&1; then
    hyprpicker -r -z >/dev/null 2>&1 &
    freeze_pid=$!
    for _ in {1..20}; do
      if hyprctl -j layers 2>/dev/null | jq -e '[.. | objects | .namespace?] | any(. == "hyprpicker")' >/dev/null; then
        ready=1
        break
      fi
      kill -0 "${freeze_pid}" 2>/dev/null || break
      sleep 0.01
    done
    ((ready)) || { kill "${freeze_pid}" 2>/dev/null || true; freeze_pid=""; }
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

capture_smart_rectangles() {
  capture_active_workspace_rectangles
}

capture_select_geometry() {
  local rectangles="$1"
  shift
  local selection=""
  local freeze_pid=""

  freeze_pid="$(capture_start_freeze)"
  selection="$(printf '%s\n' "${rectangles}" | slurp "$@" 2>/dev/null)"
  capture_stop_freeze "${freeze_pid}"
  [[ -n "${selection}" ]] || return 1
  printf '%s\n' "${selection}"
}

capture_expand_tiny_selection() {
  local selection="$1"
  local rectangles="$2"
  local rect=""

  if [[ "${selection}" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
    if (( BASH_REMATCH[3] * BASH_REMATCH[4] < 20 )); then
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

# One smart pick: window rectangles, frozen screen, and a click that lands on
# a window rather than a 1px drag. Prints "X,Y WxH"; returns 1 if cancelled.
capture_smart_select() {
  local rectangles="" selection=""

  rectangles="$(capture_smart_rectangles)"
  selection="$(capture_select_geometry "${rectangles}")" || return 1
  capture_expand_tiny_selection "${selection}" "${rectangles}"
}
