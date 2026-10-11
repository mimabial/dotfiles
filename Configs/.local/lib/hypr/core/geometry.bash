#!/usr/bin/env bash

HYPR_FALLBACK_GAPS_OUT_PX=5
HYPR_FALLBACK_BORDER_PX=2
HYPR_FALLBACK_ROUNDING_PX=2

hypr_border_metrics_into() {
  local radius_name="${1:-}"
  local width_name="${2:-}"
  local metrics=""

  [[ -n "${radius_name}" && -n "${width_name}" ]] || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 1

  local -n radius_ref="${radius_name}"
  local -n width_ref="${width_name}"

  radius_ref=""
  width_ref=""
  metrics="$(hyprctl --batch -j 'getoption decoration:rounding;getoption general:border_size' 2>/dev/null | jq -sr '[(.[0].int // ""), (.[1].int // "")] | @tsv')" || return 1
  IFS=$'\t' read -r radius_ref width_ref <<<"${metrics}"
  [[ "${radius_ref}" =~ ^[0-9]+$ && "${width_ref}" =~ ^[0-9]+$ ]]
}

hypr_resolved_gaps_out() {
  local gaps_out="${hypr_gaps_out:-}"

  if [[ ! "${gaps_out}" =~ ^[0-9]+$ ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gaps_out="$(
      if declare -F rofi_option_json >/dev/null 2>&1; then rofi_option_json general:gaps_out; else hyprctl -j getoption general:gaps_out 2>/dev/null; fi |
        jq -r '.int // ((.css // .custom // "") | split(" ")[0]) // empty' 2>/dev/null
    )"
  fi

  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out="${HYPR_FALLBACK_GAPS_OUT_PX}"
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
  unset HYPR_MONITORS_JSON_CACHE_READY HYPR_MONITORS_JSON_CACHE ROFI_HYPR_SNAPSHOT_READY
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
  local gaps_out="" ignored_border="" border_width=""

  gaps_out="$(hypr_resolved_gaps_out 2>/dev/null)"
  border_width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"
  if [[ ! "${border_width}" =~ ^[0-9]+$ ]]; then
    if declare -F rofi_option_json >/dev/null 2>&1; then
      border_width="$(rofi_option_json general:border_size | jq -r '.int // empty' 2>/dev/null || true)"
    else
      hypr_border_metrics_into ignored_border border_width 2>/dev/null || true
    fi
  fi
  [[ "${border_width}" =~ ^[0-9]+$ ]] || border_width="${HYPR_FALLBACK_BORDER_PX}"

  printf '%s\n' "$((gaps_out * 2 + border_width))"
}
