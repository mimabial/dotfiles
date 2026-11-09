#!/usr/bin/env bash
declare -F hypr_config_value_from_layers_into >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/config-layers.bash" || return 1
ROFI_PANGO_MEASURE="${BASH_SOURCE[0]%/*}/pango_measure.py"

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
      text_size="$(state_get TEXT_SIZE "${TEXT_SIZE_BASE_PX}" 2>/dev/null || true)"
    fi
    [[ "${text_size}" =~ ^[0-9]+$ ]] && scale=$((text_size * TEXT_SIZE_BASE_PT / TEXT_SIZE_BASE_PX))
  fi
  [[ -n "${scale}" ]] || scale="${TEXT_SIZE_BASE_PT}"
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
    # Layers preserve user override -> theme -> default precedence.
    hypr_config_value_from_layers_into font_name MENU_FONT || hypr_config_value_from_layers_into font_name FONT || true
    [[ -n "${font_name}" ]] || font_name="$(rofi_config_font_name 2>/dev/null || true)"
  fi
  font_name=${font_name:-monospace}
  printf '%s\n' "${font_name}"
}

rofi_font_override() {
  local font_name="$1"
  local font_scale="$2"
  printf '* {font: "%s";}\n' "$(rofi_font_description "${font_name}" "${font_scale}")"
}

rofi_font_description() {
  printf '%s %spx' "$1" "$(($2 * TEXT_SIZE_BASE_PX / TEXT_SIZE_BASE_PT))"
}

rofi_length_em_to_px_into() {
  local -n length_px_ref="$1"
  local em_value="$2"
  local font_name="$3"
  local font_scale="$4"
  local font_px=""
  local em_milli=0
  local font_milli=0
  local px_milli=0

  [[ "${em_value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  rofi_font_text_height_px_into font_px "${font_name}" "${font_scale}" || return 1
  [[ "${font_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

  em_milli="$(rofi_decimal_milli "${em_value}")" || return 1
  font_milli="$(rofi_decimal_milli "${font_px}")" || return 1
  px_milli="$(rofi_mul_milli "${em_milli}" "${font_milli}")" || return 1
  length_px_ref=$(((px_milli + ROFI_MILLI / 2) / ROFI_MILLI))
}

rofi_font_text_height_px_into() {
  local -n text_height_px_ref="$1"
  local font_name="$2"
  local font_scale="$3"
  local font_desc=""
  local measured_px=""

  [[ -n "${font_name}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  declare -gA ROFI_FONT_TEXT_HEIGHT_CACHE
  font_desc="$(rofi_font_description "${font_name}" "${font_scale}")"
  if [[ ! -v ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"] ]]; then
    measured_px="$(
      FONT_DESC="${font_desc}" python3 "${ROFI_PANGO_MEASURE}" height
    )" || return 1
    [[ -n "${measured_px}" ]] || return 1
    ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]="${measured_px}"
  fi
  text_height_px_ref="${ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]}"
}

# Measured rather than counted so nerd-font glyphs and proportional faces are not
# mistaken for one digit advance each; both extents come from one Pango pass.
rofi_font_text_extents_px() {
  local font_name="$1"
  local font_scale="$2"
  local markup="${3:-}"
  local rows="" digest="" cache_dir="" cache_file="" extents="" font_desc=""

  [[ -n "${font_name}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  IFS= read -r -d '' rows || true
  rows="${rows%"${rows##*[!$'\n']}"}"
  [[ -n "${rows}" ]] || return 1

  # menu() always runs inside $(), so a shell-variable memo would die with the
  # subshell; key the measurement on font+rows and keep it on disk instead.
  font_desc="$(rofi_font_description "${font_name}" "${font_scale}")"
  digest="$(printf '%s\n%s\n%s' "${font_desc}" "${rows}" "${markup}" | md5sum)"
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr/rofi-text-width"
  cache_file="${cache_dir}/${digest%% *}"
  if read -r extents 2>/dev/null <"${cache_file}" &&
    [[ "${extents}" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]]; then
    printf '%s\n' "${extents}"
    return 0
  fi

  extents="$(
    printf '%s\n' "${rows}" | FONT_DESC="${font_desc}" MARKUP="${markup}" python3 "${ROFI_PANGO_MEASURE}" extents
  )" || return 1

  [[ "${extents}" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]] || return 1

  mkdir -p "${cache_dir}" 2>/dev/null && printf '%s\n' "${extents}" >"${cache_file}" 2>/dev/null
  printf '%s\n' "${extents}"
}

# Measured with the Pango metrics Rofi renders with, so suffixes line up on screen.
rofi_font_align_trailing() {
  local font_name="$1" font_scale="$2" glyph="$3" target_px="${4:-0}"
  local rows="" digest="" cache_dir="" cache_file="" aligned="" font_desc=""

  [[ -n "${font_name}${glyph}" ]] && rofi_positive_decimal "${font_scale}" || return 1
  [[ "${target_px}" =~ ^[0-9]+$ ]] || target_px=0
  IFS= read -r -d '' rows || true
  rows="${rows%"${rows##*[!$'\n']}"}"
  [[ -n "${rows}" ]] || return 1

  font_desc="$(rofi_font_description "${font_name}" "${font_scale}")"
  digest="$(printf '%s\n%s\n%s\n%s' "${font_desc}" "${glyph}" "${target_px}" "${rows}" | md5sum)"
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr/rofi-trailing-align"
  cache_file="${cache_dir}/${digest%% *}"
  if [[ -s "${cache_file}" ]]; then
    printf '%s\n' "$(<"${cache_file}")"
    return 0
  fi

  aligned="$(printf '%s\n' "${rows}" | FONT_DESC="${font_desc}" GLYPH="${glyph}" \
    TARGET_PX="${target_px}" PYTHONIOENCODING=utf-8 python3 "${ROFI_PANGO_MEASURE}" align)" || return 1
  [[ -n "${aligned}" ]] || return 1
  mkdir -p "${cache_dir}" 2>/dev/null && printf '%s\n' "${aligned}" >"${cache_file}" 2>/dev/null
  printf '%s\n' "${aligned}"
}
