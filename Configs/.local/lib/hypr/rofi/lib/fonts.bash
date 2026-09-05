#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Font resolution, override emission, em->px and text->px conversion via Pango.
# External deps: hypr_config_value_from_layers (core/common).

ROFI_PANGO_MEASURE="$(dirname -- "${BASH_SOURCE[0]}")/pango_measure.py"

rofi_effective_font_scale() {
  local requested_scale="${1:-}"
  local scale="${requested_scale}"
  if [[ -n "${scale}" && ! "${scale}" =~ ^[0-9]+$ ]]; then
    printf 'WARN: invalid explicit rofi font scale: %s\n' "${scale}" >&2
    scale=""
  fi
  if [[ -z "${scale}" ]]; then
    scale="${ROFI_SCALE:-}"
    if [[ -n "${scale}" && ! "${scale}" =~ ^[0-9]+$ ]]; then
      printf 'WARN: invalid ROFI_SCALE: %s\n' "${scale}" >&2
      scale=""
    fi
  fi
  # follow the desktop text-size knob, anchored the same way it is: 12px = 1.0.
  # Callers that only required the rofi module still get it: pull state in here
  # rather than leaving them silently pinned to the default size.
  if [[ -z "${scale}" ]]; then
    local text_size="${TEXT_SIZE:-}"
    if [[ ! "${text_size}" =~ ^[0-9]+$ ]]; then
      declare -F state_get >/dev/null 2>&1 || hypr_runtime_require state >/dev/null 2>&1 || true
      text_size="$(state_get TEXT_SIZE 12 2>/dev/null || true)"
    fi
    [[ "${text_size}" =~ ^[0-9]+$ ]] && scale=$(( text_size * 10 / 12 ))
  fi
  [[ -n "${scale}" ]] || scale="10"
  printf '%s\n' "${scale}"
}

rofi_config_font_name() {
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config.rasi"
  local font_desc=""
  local line=""

  [[ -r "${config_file}" ]] || return 1
  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*font[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || continue
    font_desc="${BASH_REMATCH[1]}"
    if [[ "${font_desc}" =~ ^(.+)[[:space:]]+[0-9]+([.][0-9]+)?$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    else
      printf '%s\n' "${font_desc}"
    fi
    return 0
  done < "${config_file}"
  return 1
}

rofi_effective_font_name() {
  local requested_font="${1:-}"
  local font_name="${requested_font}"
  if [[ -z "${font_name}" ]]; then
    # font-apply keeps Rofi synchronized with the layered Hypr font setting.
    font_name="$(rofi_config_font_name 2>/dev/null || true)"
  fi
  if [[ -z "${font_name}" ]]; then
    font_name="$(hypr_config_value_from_layers "MENU_FONT" || true)"
    [[ -n "${font_name}" ]] || font_name="$(hypr_config_value_from_layers "FONT" || true)"
  fi
  font_name=${font_name:-monospace}
  printf '%s\n' "${font_name}"
}

rofi_font_override() {
  local font_name="$1"
  local font_scale="$2"
  printf '* {font: "%s %s";}\n' "${font_name}" "${font_scale}"
}

rofi_length_em_to_px() {
  local em_value="$1"
  local font_name="$2"
  local font_scale="$3"
  local font_px=""
  local em_milli=0
  local font_milli=0
  local px_milli=0

  [[ "${em_value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  font_px="$(rofi_font_text_height_px "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${font_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

  em_milli="$(rofi_decimal_milli "${em_value}")" || return 1
  font_milli="$(rofi_decimal_milli "${font_px}")" || return 1
  px_milli="$(rofi_mul_milli "${em_milli}" "${font_milli}")" || return 1
  printf '%s\n' $(((px_milli + 500) / 1000))
}

rofi_font_text_height_px() {
  local font_name="$1"
  local font_scale="$2"
  local font_desc=""
  local font_px=""

  [[ -n "${font_name}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  declare -gA ROFI_FONT_TEXT_HEIGHT_CACHE
  font_desc="${font_name} ${font_scale}"
  if [[ -v ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"] ]]; then
    printf '%s\n' "${ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]}"
    return 0
  fi

  font_px="$(
    FONT_DESC="${font_desc}" python3 "${ROFI_PANGO_MEASURE}" height
  )" || return 1

  [[ -n "${font_px}" ]] || return 1
  ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]="${font_px}"
  printf '%s\n' "${font_px}"
}

# "<widest row px> <line height px>" for the rows on stdin. Measured rather than
# counted so nerd-font glyphs and proportional faces are not mistaken for one
# digit advance each; both extents come from one Pango pass.
rofi_font_text_extents_px() {
  local font_name="$1"
  local font_scale="$2"
  local rows="" digest="" cache_dir="" cache_file="" extents="" width_px="" height_px=""

  [[ -n "${font_name}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  rows="$(cat)"
  [[ -n "${rows}" ]] || return 1

  # menu() always runs inside $(), so a shell-variable memo would die with the
  # subshell; key the measurement on font+rows and keep it on disk instead.
  digest="$(printf '%s\n%s' "${font_name} ${font_scale}" "${rows}" | md5sum)"
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr/rofi-text-width"
  cache_file="${cache_dir}/${digest%% *}"
  if read -r width_px height_px 2>/dev/null <"${cache_file}" &&
    [[ "${width_px}" =~ ^[0-9]+$ && "${height_px}" =~ ^[0-9]+$ ]]; then
    printf '%s %s\n' "${width_px}" "${height_px}"
    return 0
  fi

  extents="$(
    printf '%s\n' "${rows}" | FONT_DESC="${font_name} ${font_scale}" python3 "${ROFI_PANGO_MEASURE}" extents
  )" || return 1

  read -r width_px height_px <<<"${extents}"
  [[ "${width_px}" =~ ^[0-9]+$ && "${height_px}" =~ ^[0-9]+$ ]] || return 1

  mkdir -p "${cache_dir}" 2>/dev/null && printf '%s %s\n' "${width_px}" "${height_px}" >"${cache_file}" 2>/dev/null
  printf '%s %s\n' "${width_px}" "${height_px}"
}

# Right-align a trailing glyph across the rows that ask for one. Reads
# "<flag>\t<label>" lines and re-emits the labels alone, padding flagged ones so
# the glyph lands in a single column. target_px is the width of the text column
# the rows will be drawn in; the glyph goes to its right edge, falling back to
# the widest label when the rows are what sets that width. The pad is whole
# spaces, so the column is exact only to one space advance -- negligible in a
# mono face, and the alternative is a per-row rofi widget, which dmenu has not.
rofi_font_align_trailing() {
  local font_name="$1"
  local font_scale="$2"
  local glyph="$3"
  local target_px="${4:-0}"
  local rows="" digest="" cache_dir="" cache_file="" aligned=""

  [[ -n "${font_name}" && -n "${glyph}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  [[ "${target_px}" =~ ^[0-9]+$ ]] || target_px=0
  command -v python3 >/dev/null 2>&1 || return 1

  rows="$(cat)"
  [[ -n "${rows}" ]] || return 1

  digest="$(printf '%s\n%s\n%s\n%s' "${font_name} ${font_scale}" "${glyph}" "${target_px}" "${rows}" | md5sum)"
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr/rofi-trailing-align"
  cache_file="${cache_dir}/${digest%% *}"
  if [[ -s "${cache_file}" ]]; then
    aligned="$(<"${cache_file}")"
    printf '%s\n' "${aligned}"
    return 0
  fi

  aligned="$(
    printf '%s\n' "${rows}" |
      FONT_DESC="${font_name} ${font_scale}" GLYPH="${glyph}" TARGET_PX="${target_px}" \
        PYTHONIOENCODING=utf-8 python3 "${ROFI_PANGO_MEASURE}" align
  )" || return 1
  [[ -n "${aligned}" ]] || return 1

  mkdir -p "${cache_dir}" 2>/dev/null && printf '%s\n' "${aligned}" >"${cache_file}" 2>/dev/null
  printf '%s\n' "${aligned}"
}
