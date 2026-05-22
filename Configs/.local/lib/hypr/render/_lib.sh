#!/usr/bin/env bash
# Shared helpers for render/<app>.sh
# Source as: . "$(dirname "$0")/_lib.sh" ; render_init <app> <output-basename> [<pack-override-basename>]

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
