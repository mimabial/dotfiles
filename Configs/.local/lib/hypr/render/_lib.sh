#!/usr/bin/env bash
# Shared helpers for render/<app>.sh
# Source as: . "$(dirname "$0")/_lib.sh" ; render_init <app> <output-basename> [<pack-override-basename>]

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

# bg, fg and the sixteen numbered colours as c[0..15].
render_read_palette() {
  local -a raw=()
  mapfile -t raw < <(jq -r '.bg, .fg, (.colors[])' "${PALETTE}")
  bg="${raw[0]}" fg="${raw[1]}"
  c=("${raw[@]:2}")
}

render_palette_file() {
  printf '%s\n' "${1:-${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/active-palette.json}"
}

# Sets globals: APP, OUT_DIR, OUT_FILE, PACK_OVERRIDE, PALETTE, RENDERER_SOURCE
render_init() {
  APP="$1"
  local out_basename="$2"
  local pack_basename="${3:-${APP}.theme}"

  PALETTE="$(render_palette_file "${PALETTE_ARG:-}")"
  command -v jq >/dev/null || { echo "render/${APP}: jq required" >&2; exit 1; }
  [[ -f "${PALETTE}" ]] || { echo "render/${APP}: missing ${PALETTE}" >&2; exit 1; }

  OUT_DIR="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/${APP}"
  OUT_FILE="${OUT_DIR}/${out_basename}"
  mkdir -p "${OUT_DIR}"

  PACK_OVERRIDE=""
  local mode source
  mode="$(jq -r '.mode // ""' "${PALETTE}")"
  source="$(jq -r '.source // ""' "${PALETTE}")"
  if [[ "${mode}" == "theme" && "${source}" == theme:* ]]; then
    local candidate="${HOME}/.config/hypr/themes/${source#theme:}/${pack_basename}"
    [[ -f "${candidate}" ]] && PACK_OVERRIDE="${candidate}"
  fi

  RENDERER_SOURCE="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
}

# Exits the renderer outright when its inputs are unchanged; otherwise opens the
# temp file the caller writes to and arms its cleanup. Sets hash and tmp.
render_begin() {
  hash="$(render_input_hash)"
  render_should_skip "${hash}" && exit 0
  tmp="$(render_temp)"
  trap 'rm -f "${tmp}"' EXIT
}

render_input_hash() {
  {
    cat "${PALETTE}"
    [[ -n "${PACK_OVERRIDE}" ]] && cat "${PACK_OVERRIDE}"
    cat "${RENDERER_SOURCE}"
  } | { xxh64sum 2>/dev/null || md5sum; } | awk '{print $1}'
}

# Returns 0 (skip) when cache hits and output exists; 1 otherwise.
render_should_skip() {
  local hash="$1"
  render-cache hit? "${APP}" "${hash}" && [[ -f "${OUT_FILE}" ]]
}

# Echoes a temp file path inside OUT_DIR. Caller writes to it, then calls render_commit.
render_temp() {
  mktemp "${OUT_DIR}/.$(basename "${OUT_FILE}").XXXXXX"
}

render_commit() {
  local tmp="$1" hash="$2"
  mv -f "${tmp}" "${OUT_FILE}"
  render-cache store "${APP}" "${hash}"
}

# Copies a pack-override file verbatim, skipping the first line if it's the conventional
# "$HOME/..." target-path header used in the dotfiles' .theme format.
render_emit_pack_override() {
  local tmp="$1"
  local first
  first="$(head -n1 "${PACK_OVERRIDE}")"
  if [[ "${first}" == \$* ]]; then
    tail -n +2 "${PACK_OVERRIDE}" > "${tmp}"
  else
    cp "${PACK_OVERRIDE}" "${tmp}"
  fi
}
