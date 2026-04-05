#!/usr/bin/env bash

hypr_core_file() {
  local rel_path="$1"
  local config_home="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local data_home="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}"
  local shared_file="${data_home}/${rel_path}"
  local user_file="${config_home}/${rel_path}"

  if [[ -f "${shared_file}" ]]; then
    printf '%s\n' "${shared_file}"
  elif [[ -f "${user_file}" ]]; then
    printf '%s\n' "${user_file}"
  else
    # Prefer shared path as canonical target for new writes/read attempts.
    printf '%s\n' "${shared_file}"
  fi
}

hypr_variables_file() {
  hypr_core_file "variables.conf"
}

hypr_config_layer_files() {
  local config_home="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local data_home="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}"
  local variables_file="${data_home}/variables.conf"

  [[ -f "${variables_file}" ]] || variables_file="${config_home}/variables.conf"

  printf '%s\n' \
    "${config_home}/themes/theme.conf" \
    "${config_home}/userfonts.conf" \
    "${variables_file}"
}

hypr_trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

hypr_config_value_from_layers() {
  local variable_key="${1#\$}"
  local file_path=""
  local raw_line=""
  local lhs=""
  local rhs=""
  local value=""

  [[ -n "${variable_key}" ]] || return 1

  while IFS= read -r file_path; do
    [[ -f "${file_path}" ]] || continue
    if [[ ! -r "${file_path}" ]]; then
      printf 'ERROR: cannot read Hypr config file: %s\n' "${file_path}" >&2
      continue
    fi

    while IFS= read -r raw_line; do
      [[ -n "${raw_line//[[:space:]]/}" ]] || continue
      [[ ! "${raw_line}" =~ ^[[:space:]]*# ]] || continue
      [[ "${raw_line}" == *=* ]] || continue

      lhs="${raw_line%%=*}"
      rhs="${raw_line#*=}"
      lhs="$(hypr_trim_whitespace "${lhs}")"
      [[ "${lhs}" == "\$${variable_key}" ]] || continue

      rhs="${rhs%%#*}"
      rhs="$(hypr_trim_whitespace "${rhs}")"
      rhs="${rhs%\'}"
      rhs="${rhs#\'}"
      rhs="${rhs%\"}"
      rhs="${rhs#\"}"

      if [[ -z "${rhs}" ]]; then
        printf 'WARN: invalid empty $%s in %s\n' "${variable_key}" "${file_path}" >&2
        break
      fi

      value="${rhs}"
      printf '%s\n' "${value}"
      return 0
    done < "${file_path}"
  done < <(hypr_config_layer_files)

  return 1
}

hypr_border_metrics() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  hyprctl --batch -j "getoption decoration:rounding;getoption general:border_size" 2>/dev/null |
    jq -s -r '[.[0].int // empty, .[1].int // empty] | @tsv' 2>/dev/null
}

hypr_resolved_gaps_out() {
  local gaps_out="${hypr_gaps_out:-}"

  if [[ ! "${gaps_out}" =~ ^[0-9]+$ ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gaps_out="$(
      hyprctl -j getoption general:gaps_out 2>/dev/null |
        jq -r '.int // empty' 2>/dev/null
    )"
  fi

  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5
  printf '%s\n' "${gaps_out}"
}

hypr_focused_monitor_geometry() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  hyprctl -j monitors \
    | jq -r '
        (map(select(.focused == true))[0] // .[0]) as $monitor
        | [
            ($monitor.x // 0),
            ($monitor.y // 0),
            ($monitor.width // 0),
            ($monitor.height // 0),
            ($monitor.scale // 1),
            ($monitor.reserved[0] // 0),
            ($monitor.reserved[1] // 0),
            ($monitor.reserved[2] // 0),
            ($monitor.reserved[3] // 0)
          ]
        | @tsv
      ' \
    | awk -F '\t' '{ scale = ($5 > 0 ? $5 : 1); printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", $1 / scale, $2 / scale, $3 / scale, $4 / scale, $6, $7, $8, $9 }'
}

hypr_window_edge_padding_px() {
  local gaps_out=5
  local border_width=2
  local metrics=""

  gaps_out="$(hypr_resolved_gaps_out 2>/dev/null || true)"
  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5

  border_width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"
  if [[ ! "${border_width}" =~ ^[0-9]+$ ]]; then
    metrics="$(hypr_border_metrics 2>/dev/null || true)"
    if [[ -n "${metrics}" ]]; then
      IFS=$'\t' read -r _ border_width <<< "${metrics}"
    fi
  fi
  [[ "${border_width}" =~ ^[0-9]+$ ]] || border_width=2

  printf '%s\n' "$((gaps_out * 2 + border_width))"
}

hypr_compact_path() {
  local path="$1"
  local var_name=""
  local base_path=""

  for var_name in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME HOME; do
    base_path="${!var_name:-}"
    [[ -n "${base_path}" && "${path}" == "${base_path}"/* ]] || continue
    printf '$%s%s\n' "${var_name}" "${path#${base_path}}"
    return 0
  done

  printf '%s\n' "${path}"
}
