#!/usr/bin/env bash
# Non-interactive clipboard API used by Quickshell.

cliphist_panel_json() {
  local favorites_file="$1" favorites_json="[]"
  if [[ -s "${favorites_file}" ]]; then
    favorites_json="$(
      while IFS= read -r encoded; do
        [[ -n "${encoded}" ]] || continue
        printf '%s' "${encoded}" | base64 --decode 2>/dev/null | tr '\n' ' '
        printf '\n'
      done <"${favorites_file}" | jq -R -s 'split("\n") | map(select(length > 0)) |
        to_entries | map({index: (.key + 1), text: .value})'
    )"
  fi

  cliphist list | jq -R -s --argjson favorites "${favorites_json}" '
    split("\n") | map(select(length > 0)) | map(split("\t") | {
      id: .[0], preview: (.[1:] | join("\t"))
    }) | map(. + {image: (.preview | test("\\[\\[ binary data"))})
    | {entries: ., favorites: $favorites}'
}

cliphist_panel_copy() {
  local id="$1"
  [[ "${id}" =~ ^[0-9]+$ ]] || return 1
  printf '%s\t' "${id}" | cliphist decode | wl-copy
  printf '%s\t' "${id}" | cliphist delete
  sleep "${CLIPHIST_PASTE_DELAY:-0.2}"
  paste_string
}

cliphist_panel_delete() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  printf '%s\t' "$1" | cliphist delete
}

cliphist_panel_favorite_add() {
  local favorites_file="$1" id="$2" encoded="" status=0
  [[ "${id}" =~ ^[0-9]+$ ]] || return 1
  encoded="$(printf '%s\t' "${id}" | cliphist decode | base64 -w 0)" || return 1
  cliphist_favorite_add_encoded "${favorites_file}" "${encoded}" || status=$?
  [[ "${status}" -eq 2 ]] && return 0
  return "${status}"
}

cliphist_panel_favorite_copy() {
  local encoded=""
  encoded="$(cliphist_favorite_at "$1" "$2")" || return 1
  printf '%s' "${encoded}" | base64 --decode | wl-copy
}

cliphist_panel_dispatch() {
  local favorites_file="$1" action="${2:-}" argument="${3:-}"
  case "${action}" in
    --panel-json) [[ "$#" -eq 2 ]] && cliphist_panel_json "${favorites_file}" ;;
    --panel-copy) [[ "$#" -eq 3 ]] && cliphist_panel_copy "${argument}" ;;
    --panel-delete) [[ "$#" -eq 3 ]] && cliphist_panel_delete "${argument}" ;;
    --panel-fav-add) [[ "$#" -eq 3 ]] && cliphist_panel_favorite_add "${favorites_file}" "${argument}" ;;
    --panel-fav-remove) [[ "$#" -eq 3 ]] && cliphist_favorite_remove_index "${favorites_file}" "${argument}" ;;
    --panel-fav-copy) [[ "$#" -eq 3 ]] && cliphist_panel_favorite_copy "${favorites_file}" "${argument}" ;;
    *) return 2 ;;
  esac
}
