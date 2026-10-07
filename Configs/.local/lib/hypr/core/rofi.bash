#!/usr/bin/env bash

rofi_user_dir() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
}

rofi_shared_dir() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/rofi"
}

rofi_lookup_dirs() {
  case "${1}" in
    theme)
      printf '%s\n' \
        "$(rofi_user_dir)/themes" \
        "$(rofi_user_dir)" \
        "$(rofi_shared_dir)/themes" \
        "$(rofi_shared_dir)"
      ;;
    asset)
      printf '%s\n' \
        "$(rofi_user_dir)/assets" \
        "$(rofi_user_dir)" \
        "$(rofi_shared_dir)/assets" \
        "$(rofi_shared_dir)"
      ;;
    *)
      return 1
      ;;
  esac
}

rofi_resolve_file() {
  local kind="$1"
  local ref="$2"
  local dir=""
  local candidate=""
  local -a lookup_dirs=()

  [[ -n "${ref}" ]] || return 1
  [[ -f "${ref}" ]] && {
    printf '%s\n' "${ref}"
    return 0
  }

  mapfile -t lookup_dirs < <(rofi_lookup_dirs "${kind}")
  for dir in "${lookup_dirs[@]}"; do
    [[ -n "${dir}" ]] || continue
    case "${kind}" in
      theme)
        for candidate in "${dir}/${ref}.rasi" "${dir}/${ref}"; do
          [[ -f "${candidate}" ]] || continue
          printf '%s\n' "${candidate}"
          return 0
        done
        ;;
      asset)
        candidate="${dir}/${ref}"
        [[ -f "${candidate}" ]] || continue
        printf '%s\n' "${candidate}"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  done

  case "${kind}" in
    theme) printf '%s\n' "$(rofi_shared_dir)/themes/${ref}.rasi" ;;
    asset) printf '%s\n' "$(rofi_shared_dir)/assets/${ref}" ;;
  esac
  return 1
}

rofi_list_files() {
  local kind="$1"
  local pattern="${2:-*}"
  local dir=""
  local file=""
  local base=""
  local -A seen=()

  while IFS= read -r dir; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r file; do
      base="$(basename "${file}")"
      [[ -n "${seen[${base}]:-}" ]] && continue
      seen["${base}"]=1
      printf '%s\n' "${file}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name "${pattern}" | sort)
  done < <(
    case "${kind}" in
      theme) printf '%s\n%s\n' "$(rofi_user_dir)/themes" "$(rofi_shared_dir)/themes" ;;
      asset) printf '%s\n%s\n' "$(rofi_user_dir)/assets" "$(rofi_shared_dir)/assets" ;;
      *) return 1 ;;
    esac
  )
}

rofi_resolve_theme() {
  rofi_resolve_file theme "$1"
}

rofi_resolve_asset() {
  rofi_resolve_file asset "$1"
}

rofi_list_theme_files() {
  rofi_list_files theme '*.rasi'
}

rofi_list_asset_files() {
  rofi_list_files asset "${1:-*}"
}

rofi_resolve_monitors_json() {
  if declare -F rofi_monitors_json >/dev/null 2>&1; then
    rofi_monitors_json
  elif declare -F hypr_monitors_json >/dev/null 2>&1; then
    hypr_monitors_json
  else
    hyprctl -j monitors all 2>/dev/null || true
  fi
}

rofi_monitor_record() {
  local selector="$1"
  shift
  local monitors_json=""

  monitors_json="$(rofi_resolve_monitors_json)"
  [[ -n "${monitors_json}" ]] || return 1

  printf '%s\n' "${monitors_json}" |
    jq -r "$@" "def monitor_width: if (.transform % 2 == 0) then .width else .height end;
def monitor_height: if (.transform % 2 == 0) then .height else .width end;
def record: [
  monitor_width,
  monitor_height,
  (.scale // 1),
  (.x // 0),
  (.y // 0),
  (.reserved[0] // 0),
  (.reserved[1] // 0),
  (.reserved[2] // 0),
  (.reserved[3] // 0)
] | @tsv;
${selector} | record" 2>/dev/null | head -n 1
}

rofi_focused_monitor_record() {
  rofi_monitor_record '.[] | select(.focused == true)'
}

rofi_default_window_size() {
  local width_name="$1"
  local height_name="$2"
  local -n width_ref="${width_name}"
  local -n height_ref="${height_name}"
  local font_scale="${ROFI_SCALE:-10}"

  if [[ "${width_ref}" -eq 0 && "${height_ref}" -eq 0 ]]; then
    local default_width_em=23
    local default_height_em=30
    width_ref=$((default_width_em * font_scale * ROFI_EM_PX_PER_SCALE))
    height_ref=$((default_height_em * font_scale * ROFI_EM_PX_PER_SCALE))
  fi
}

rofi_scale_milli() {
  local scale="${1:-1}"
  local whole_part=""
  local fraction_part=""

  if [[ "${scale}" =~ ^([0-9]+)([.]([0-9]+))?$ ]]; then
    whole_part="${BASH_REMATCH[1]}"
    fraction_part="${BASH_REMATCH[3]:-}"
    fraction_part="${fraction_part:0:3}"

    while ((${#fraction_part} < 3)); do
      fraction_part="${fraction_part}0"
    done

    if [[ "${whole_part}" != "0" || "${fraction_part}" != "000" ]]; then
      printf '%s\n' $((10#${whole_part} * ROFI_MILLI + 10#${fraction_part:-000}))
      return 0
    fi
  fi

  printf '1000\n'
}

ROFI_MILLI=1000

rofi_scaled_divide() {
  local value="${1:-0}"
  local scale="${2:-1}"
  local min_value="${3:-}"
  local scale_milli=""
  local result=0

  [[ "${value}" =~ ^-?[0-9]+$ ]] || value=0
  scale_milli="$(rofi_scale_milli "${scale}")"
  result=$((value * ROFI_MILLI / scale_milli))

  if [[ -n "${min_value}" ]] && [[ "${result}" -lt "${min_value}" ]]; then
    result="${min_value}"
  fi

  printf '%s\n' "${result}"
}

ROFI_CURSOR_GAP_PX=8
ROFI_FALLBACK_EDGE_PADDING_PX=12

rofi_cursor_position() {
  local cursor_x=0 cursor_y=0

  IFS=$'\t' read -r cursor_x cursor_y < <(
    if declare -F rofi_cursor_json >/dev/null 2>&1; then rofi_cursor_json; else hyprctl cursorpos -j 2>/dev/null; fi |
      jq -r '[(.x // 0 | floor), (.y // 0 | floor)] | @tsv' 2>/dev/null
  )
  [[ "${cursor_x}" =~ ^-?[0-9]+$ ]] || cursor_x=0
  [[ "${cursor_y}" =~ ^-?[0-9]+$ ]] || cursor_y=0
  printf '%s\t%s\n' "${cursor_x}" "${cursor_y}"
}

rofi_monitor_under_cursor() {
  rofi_monitor_record '
    (
      .[] | select(
        ($cx >= .x) and
        ($cx < (.x + monitor_width)) and
        ($cy >= .y) and
        ($cy < (.y + monitor_height))
      )
    ),
    (.[] | select(.focused == true))
  ' --argjson cx "$1" --argjson cy "$2"
}

rofi_window_position_theme() {
  local window_width="${1:-0}"
  local window_height="${2:-0}"
  local cursor_x=0 cursor_y=0 monitor_line=""
  local parsed_width=0 parsed_height=0 parsed_scale=1 mon_x=0 mon_y=0
  local off_left=0 off_top=0 off_right=0 off_bottom=0
  local mon_width=0 mon_height=0 edge_padding=0 usable_width=0 usable_height=0
  local max_x=0 max_y=0 x_off=0 y_off=0

  rofi_default_window_size window_width window_height
  IFS=$'\t' read -r cursor_x cursor_y < <(rofi_cursor_position)
  monitor_line="$(rofi_monitor_under_cursor "${cursor_x}" "${cursor_y}")" || return 1
  [[ -n "${monitor_line}" ]] || return 1

  IFS=$'\t' read -r parsed_width parsed_height parsed_scale mon_x mon_y \
    off_left off_top off_right off_bottom <<<"${monitor_line}"
  [[ "${parsed_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || parsed_scale=1
  mon_width="$(rofi_scaled_divide "${parsed_width}" "${parsed_scale}" 1)"
  mon_height="$(rofi_scaled_divide "${parsed_height}" "${parsed_scale}" 1)"
  edge_padding="$(hypr_window_edge_padding_px 2>/dev/null || true)"
  [[ "${edge_padding}" =~ ^[0-9]+$ ]] || edge_padding="${ROFI_FALLBACK_EDGE_PADDING_PX}"

  usable_width=$((mon_width - off_left - off_right))
  usable_height=$((mon_height - off_top - off_bottom))
  ((usable_width < 1)) && usable_width=1
  ((usable_height < 1)) && usable_height=1
  max_x=$((usable_width - window_width - edge_padding))
  max_y=$((usable_height - window_height - edge_padding))
  ((max_x < edge_padding)) && max_x="${edge_padding}"
  ((max_y < edge_padding)) && max_y="${edge_padding}"

  # cursorpos and monitor x/y are logical; only width/height need descaling
  x_off="$(hypr_clamp $((cursor_x - mon_x - off_left + ROFI_CURSOR_GAP_PX)) "${edge_padding}" "${max_x}")"
  y_off="$(hypr_clamp $((cursor_y - mon_y - off_top + ROFI_CURSOR_GAP_PX)) "${edge_padding}" "${max_y}")"
  printf 'window{location:%s %s;anchor:%s %s;x-offset:%spx;y-offset:%spx;}\n' \
    west north west north "${x_off}" "${y_off}"
}
