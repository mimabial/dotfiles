#!/usr/bin/env bash

# The role names every renderer resolves a palette to, as two jq fragments so a
# caller can splice its own aliases between them and still emit the same key
# order in one jq invocation.
RENDER_PALETTE_ROLES_JQ='
  .colors as $c | {
    bg: .bg, fg: .fg, br: $c[5],
    alt_bg: $c[6], alt_fg: $c[3], alt_br: $c[11],
    fg_selected: $c[4],
    act_bg: $c[8], act_fg: $c[7], act_br: $c[13],
    hvr_bg: .bg, hvr_fg: .fg, hvr_br: $c[12],
    accent: $c[12], info: $c[6], warning: $c[3], error: $c[1], success: $c[2]
  }'
RENDER_PALETTE_NUMBERED_JQ='
  + ([range(0; 16)] | map({key: ("c" + tostring), value: $c[.]}) | from_entries)'
RENDER_ANSI_COLOR_COUNT=16
RENDER_CONFIG_DIR="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
RENDER_CACHE_DIR="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
RENDER_HASH_DIR="${RENDER_CACHE_DIR}/render-hashes"

render_job_into() {
  local -n job_ref="$1"
  local palette_file="${2:-${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/active-palette.json}"
  local app="$3" output_basename="$4" pack_basename="${5-${3}.theme}"
  command -v jq >/dev/null || { printf 'render/%s: jq required\n' "${app}" >&2; return 1; }
  [[ -f "${palette_file}" ]] || { printf 'render/%s: missing %s\n' "${app}" "${palette_file}" >&2; return 1; }
  local metadata="" mode="" source="" pack_override=""
  metadata="$(jq -r '.mode // "", .source // ""' "${palette_file}")" || return 1
  mode="${metadata%%$'\n'*}" source="${metadata#*$'\n'}"
  if [[ "${mode}" == theme && "${source}" == theme:* ]]; then
    pack_override="${RENDER_CONFIG_DIR}/themes/${source#theme:}/${pack_basename}"
    [[ -f "${pack_override}" ]] || pack_override=""
  fi
  job_ref=(
    [app]="${app}" [palette_file]="${palette_file}"
    [output_file]="${RENDER_CACHE_DIR}/render/${app}/${output_basename}"
    [pack_override]="${pack_override}" [palette_mode]="${mode}" [palette_source]="${source}"
    [renderer_file]="${BASH_SOURCE[1]}"
  )
  job_ref[input_digest]="$(render_input_digest "$1")"
}

render_read_palette_into() {
  local -n job_ref="$1"
  local -a palette_values=()
  mapfile -t palette_values < <(jq -r '.bg, .fg, (.cursor // .fg), (.colors[])' "${job_ref[palette_file]}")
  job_ref[background_color]="${palette_values[0]}" job_ref[foreground_color]="${palette_values[1]}"
  job_ref[cursor_color]="${palette_values[2]}"
  local index
  for ((index = 3; index < ${#palette_values[@]}; index++)); do
    job_ref["color$((index - 3))"]="${palette_values[index]}"
  done
}

render_input_digest() {
  local -n job_ref="$1"
  local -a inputs=("${job_ref[palette_file]}")
  [[ -z "${job_ref[pack_override]}" ]] || inputs+=("${job_ref[pack_override]}")
  inputs+=("${job_ref[renderer_file]}" "${BASH_SOURCE[0]}")
  cat "${inputs[@]}" | render_digest
}

render_digest() {
  local digest
  digest="$({ xxh64sum 2>/dev/null || md5sum; })" || return 1
  printf '%s\n' "${digest%% *}"
}

render_fold_stdin_into_input_digest() {
  local -n job_ref="$1"
  job_ref[input_digest]="$({ printf '%s\n' "${job_ref[input_digest]}"; cat; } | render_digest)"
}

render_output_is_current() {
  local -n job_ref="$1"
  local stored_digest="${RENDER_HASH_DIR}/${job_ref[app]}"
  [[ "${HYPR_FORCE_REGEN:-0}" != 1 && -n "${job_ref[input_digest]}" && -f "${stored_digest}" && -f "${job_ref[output_file]}" ]] &&
    [[ "$(<"${stored_digest}")" == "${job_ref[input_digest]}" ]]
}

render_store_input_digest() {
  local -n job_ref="$1"
  [[ "${HYPR_NO_CACHE:-0}" != 1 ]] || return 0
  mkdir -p "${RENDER_HASH_DIR}" || return 1
  local staged_digest
  staged_digest="$(mktemp "${RENDER_HASH_DIR}/.${job_ref[app]}.XXXXXX")" || return 1
  printf '%s\n' "${job_ref[input_digest]}" >"${staged_digest}"
  mv -f -- "${staged_digest}" "${RENDER_HASH_DIR}/${job_ref[app]}"
}

render_stage_output_into() {
  local -n job_ref="$1"
  local output_file="${job_ref[output_file]}"
  mkdir -p "${output_file%/*}" || return 1
  job_ref[staged_file]="$(mktemp "${output_file%/*}/.${output_file##*/}.XXXXXX")"
}

render_link_output() {
  local -n job_ref="$1"
  local link="$2"
  [[ -L "${link}" ]] || { mkdir -p "${link%/*}" && ln -sfn "${job_ref[output_file]}" "${link}"; }
}

render_commit_staged_output() {
  local -n job_ref="$1"
  mv -f -- "${job_ref[staged_file]}" "${job_ref[output_file]}" || return 1
  render_store_input_digest "$1"
}

# A .theme file may open with the dotfiles' "$HOME/..." target-path header, which
# is not part of the theme.
render_write_pack_override() {
  local -n job_ref="$1"
  local first_line=""
  IFS= read -r first_line <"${job_ref[pack_override]}" || true
  if [[ "${first_line}" == \$* ]]; then
    tail -n +2 "${job_ref[pack_override]}" >"${job_ref[staged_file]}"
  else
    cp -- "${job_ref[pack_override]}" "${job_ref[staged_file]}"
  fi
}
