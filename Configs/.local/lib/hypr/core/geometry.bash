#!/usr/bin/env bash

HYPR_FALLBACK_GAPS_OUT_PX=5
HYPR_FALLBACK_BORDER_PX=2
HYPR_FALLBACK_ROUNDING_PX=2
HYPR_BORDER_METRICS_QUERY='getoption decoration:rounding;getoption general:border_size'

hypr_border_metrics_parse_into() {
  local -n parsed_radius_ref="$1"
  local -n parsed_width_ref="$2"

  [[ "$3" =~ \"int\":[[:space:]]*(-?[0-9]+).*\"int\":[[:space:]]*(-?[0-9]+) ]] || return 1
  parsed_radius_ref="${BASH_REMATCH[1]}"
  parsed_width_ref="${BASH_REMATCH[2]}"
  [[ "${parsed_radius_ref}" =~ ^[0-9]+$ && "${parsed_width_ref}" =~ ^[0-9]+$ ]]
}

hypr_load_border_metrics() {
  local metrics_json=""

  [[ -z "${HYPR_BORDER_METRICS_LOADED:-}" ]] || return 0
  [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || metrics_json="$(hyprctl --batch -j "${HYPR_BORDER_METRICS_QUERY}" 2>/dev/null)" || metrics_json=""
  hypr_load_border_metrics_from_json "${metrics_json}"
}

hypr_load_border_metrics_from_json() {
  local live_radius=""
  local live_width=""

  [[ -z "${HYPR_BORDER_METRICS_LOADED:-}" ]] || return 0
  hypr_border_metrics_parse_into live_radius live_width "$1" || true
  HYPR_BORDER_METRICS_LOADED=1
  HYPR_RUNTIME_BORDER_RADIUS="${live_radius:-${HYPR_BORDER_RADIUS:-${HYPR_FALLBACK_ROUNDING_PX}}}"
  HYPR_RUNTIME_BORDER_WIDTH="${live_width:-${HYPR_BORDER_WIDTH:-${HYPR_FALLBACK_BORDER_PX}}}"
}

hypr_gaps_out_json_prime() {
  declare -g HYPR_GAPS_OUT_JSON_CACHE="$1"
}

hypr_resolved_gaps_out() {
  local gaps_out="${HYPR_FALLBACK_GAPS_OUT_PX}"

  [[ -v HYPR_GAPS_OUT_JSON_CACHE ]] || hypr_gaps_out_json_prime "$(hyprctl -j getoption general:gaps_out 2>/dev/null)"
  [[ "${HYPR_GAPS_OUT_JSON_CACHE}" =~ \"(int|css|custom)\":[[:space:]]*\"?([0-9]+) ]] && gaps_out="${BASH_REMATCH[2]}"
  printf '%s\n' "${gaps_out}"
}

hypr_monitors_json_prime() {
  declare -g HYPR_MONITORS_JSON_CACHE_READY=1
  declare -g HYPR_MONITORS_JSON_CACHE="$1"
}

hypr_monitors_json() {
  [[ -n "${HYPR_MONITORS_JSON_CACHE_READY:-}" ]] \
    || hypr_monitors_json_prime "$(hyprctl -j monitors all 2>/dev/null || true)"
  printf '%s\n' "${HYPR_MONITORS_JSON_CACHE}"
}

hypr_monitors_invalidate() {
  unset HYPR_MONITORS_JSON_CACHE_READY HYPR_MONITORS_JSON_CACHE
}

hypr_select_monitor_geometry_into() {
  local -n geometry_ref="$1"
  local selector="$2" field value
  shift 2

  geometry_ref=()
  while IFS=$'\t' read -r field value; do
    geometry_ref["${field}"]="${value}"
  done < <(jq -r "$@" "
    def monitor_scale: (.scale // 1) | if . > 0 then . else 1 end;
    def physical_width_px: if ((.transform // 0) % 2 == 0) then (.width // 0) else (.height // 0) end;
    def physical_height_px: if ((.transform // 0) % 2 == 0) then (.height // 0) else (.width // 0) end;
    def logical_width_px: (physical_width_px / monitor_scale | trunc) + 0;
    def logical_height_px: (physical_height_px / monitor_scale | trunc) + 0;
    first(${selector}) | select(. != null) | {
      physical_width_px: physical_width_px,
      physical_height_px: physical_height_px,
      scale: (.scale // 1),
      logical_x_px: (.x // 0),
      logical_y_px: (.y // 0),
      logical_width_px: logical_width_px,
      logical_height_px: logical_height_px,
      reserved_left_px: (.reserved[0] // 0),
      reserved_top_px: (.reserved[1] // 0),
      reserved_right_px: (.reserved[2] // 0),
      reserved_bottom_px: (.reserved[3] // 0)
    } | to_entries[] | [.key, .value] | @tsv
  ")
  [[ -n "${geometry_ref[logical_width_px]:-}" ]]
}

hypr_monitor_geometry_into() {
  local output_name="$1" selector="${2:-}" monitors_json=""

  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  monitors_json="$(hypr_monitors_json)" || return 1
  hypr_select_monitor_geometry_into "${output_name}" '
    if $selector == "" then
      map(select(.focused == true))[0] // .[0]
    elif $selector | test("^[0-9]+$") then
      map(select((.id | tostring) == $selector))[0]
    else
      map(select(.name == $selector))[0]
    end
  ' --arg selector "${selector}" <<<"${monitors_json}"
}

hypr_window_edge_padding_px() {
  local gaps_out="" border_width=""

  gaps_out="$(hypr_resolved_gaps_out 2>/dev/null)"
  [[ -n "${hypr_width:-}" ]] || hypr_load_border_metrics
  border_width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"
  [[ "${border_width}" =~ ^[0-9]+$ ]] || border_width="${HYPR_FALLBACK_BORDER_PX}"

  printf '%s\n' "$((gaps_out * 2 + border_width))"
}
