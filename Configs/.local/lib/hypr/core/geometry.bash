#!/usr/bin/env bash

hypr_border_metrics_into() {
  local border_name="${1:-}"
  local width_name="${2:-}"
  local metrics=""

  [[ -n "${border_name}" && -n "${width_name}" ]] || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 1

  local -n border_ref="${border_name}"
  local -n width_ref="${width_name}"

  border_ref=""
  width_ref=""
  metrics="$(hyprctl --batch -j 'getoption decoration:rounding;getoption general:border_size' 2>/dev/null | jq -sr '[(.[0].int // ""), (.[1].int // "")] | @tsv')" || return 1
  IFS=$'\t' read -r border_ref width_ref <<<"${metrics}"
  [[ "${border_ref}" =~ ^[0-9]+$ && "${width_ref}" =~ ^[0-9]+$ ]]
}

hypr_resolved_gaps_out() {
  local gaps_out="${hypr_gaps_out:-}"

  if [[ ! "${gaps_out}" =~ ^[0-9]+$ ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gaps_out="$(
      if declare -F rofi_option_json >/dev/null 2>&1; then rofi_option_json general:gaps_out; else hyprctl -j getoption general:gaps_out 2>/dev/null; fi |
        jq -r '.int // ((.css // .custom // "") | split(" ")[0]) // empty' 2>/dev/null
    )"
  fi

  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5
  printf '%s\n' "${gaps_out}"
}

hypr_monitors_json() {
  if [[ -z "${HYPR_MONITORS_JSON_CACHE_READY:-}" ]]; then
    declare -g HYPR_MONITORS_JSON_CACHE_READY=1
    declare -g HYPR_MONITORS_JSON_CACHE
    HYPR_MONITORS_JSON_CACHE="$(hyprctl -j monitors all 2>/dev/null || true)"
  fi
  printf '%s\n' "${HYPR_MONITORS_JSON_CACHE}"
}

hypr_monitors_invalidate() {
  unset HYPR_MONITORS_JSON_CACHE_READY HYPR_MONITORS_JSON_CACHE ROFI_HYPR_SNAPSHOT_READY
}

hypr_monitor_geometry() {
  local selector="${1:-}"

  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  hypr_monitors_json \
    | jq -r --arg selector "${selector}" '
        (
          if $selector == "" then
            map(select(.focused == true))[0] // .[0]
          elif $selector | test("^[0-9]+$") then
            map(select((.id | tostring) == $selector))[0]
          else
            map(select(.name == $selector))[0]
          end
        ) as $monitor | select($monitor != null)
        | (($monitor.scale // 1) | if . > 0 then . else 1 end) as $scale
        | [
            ((($monitor.x // 0) / $scale | trunc) + 0),
            ((($monitor.y // 0) / $scale | trunc) + 0),
            ((($monitor.width // 0) / $scale | trunc) + 0),
            ((($monitor.height // 0) / $scale | trunc) + 0),
            ($monitor.reserved[0] // 0),
            ($monitor.reserved[1] // 0),
            ($monitor.reserved[2] // 0),
            ($monitor.reserved[3] // 0)
          ]
        | @tsv
      '
}

hypr_window_edge_padding_px() {
  local gaps_out=5
  local ignored_border=""
  local border_width=2

  gaps_out="$(hypr_resolved_gaps_out 2>/dev/null || true)"
  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5

  border_width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"
  if [[ ! "${border_width}" =~ ^[0-9]+$ ]]; then
    if declare -F rofi_option_json >/dev/null 2>&1; then
      border_width="$(rofi_option_json general:border_size | jq -r '.int // empty' 2>/dev/null || true)"
    else
      hypr_border_metrics_into ignored_border border_width 2>/dev/null || true
    fi
  fi
  [[ "${border_width}" =~ ^[0-9]+$ ]] || border_width=2

  printf '%s\n' "$((gaps_out * 2 + border_width))"
}
