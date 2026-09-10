#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

cliphist_favorites_path() {
  local legacy_file="${HOME}/.cliphist_favorites"
  [[ -f "${legacy_file}" ]] && printf '%s\n' "${legacy_file}" ||
    printf '%s/landing/cliphist_favorites\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

cliphist_favorite_at() {
  local file="$1" line_number="$2"
  [[ "${line_number}" =~ ^[1-9][0-9]*$ && -f "${file}" ]] || return 1
  awk -v line_number="${line_number}" 'NR == line_number { print; exit }' "${file}"
}

cliphist_favorite_add_encoded() {
  local file="$1" encoded="$2"
  [[ -n "${encoded}" ]] || return 1
  mkdir -p "$(dirname "${file}")" || return 1
  [[ -f "${file}" ]] && grep -Fxq -- "${encoded}" "${file}" && return 2
  printf '%s\n' "${encoded}" >>"${file}"
}

cliphist_favorite_remove_encoded() {
  local file="$1" encoded="$2" temporary=""
  [[ -f "${file}" && -n "${encoded}" ]] || return 1
  temporary="$(mktemp "$(dirname "${file}")/.cliphist_favorites.XXXXXX")" || return 1
  awk -v encoded="${encoded}" '$0 != encoded' "${file}" >"${temporary}" &&
    mv "${temporary}" "${file}" && return 0
  rm -f "${temporary}"
  return 1
}

cliphist_favorite_remove_index() {
  local file="$1" index="$2" encoded=""
  encoded="$(cliphist_favorite_at "${file}" "${index}")" || return 1
  [[ -n "${encoded}" ]] || return 1
  cliphist_favorite_remove_encoded "${file}" "${encoded}"
}
