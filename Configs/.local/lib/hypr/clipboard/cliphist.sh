#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_help_guard "Usage: hyprshell clipboard/cliphist --panel-json | --wipe | --panel-{copy,delete,image,fav-add} ID | --panel-fav-{copy,remove} N | --scan-{image,qr} ID" "$@"

favorites_file="${XDG_CACHE_HOME:-$HOME/.cache}/landing/cliphist_favorites"
OCR_ERROR_NOTIFY_MS=7000

panel_json() {
  local favorites=""
  [[ -f "${favorites_file}" ]] && favorites="$(<"${favorites_file}")"
  cliphist list | jq -R -s --arg favorites "${favorites}" '
    def rows: split("\n") | map(select(length > 0));
    {
      entries: rows | map(split("\t") | {id: .[0], preview: (.[1:] | join("\t"))}
        | .image = (.preview | test("\\[\\[ binary data"))),
      favorites: $favorites | rows | to_entries
        | map({index: (.key + 1), text: (.value | @base64d | gsub("\n"; " "))})
    }'
}

# wl-copy stores the entry again as the newest, which leaves the original id as a duplicate
copy_entry() {
  hypr_runtime_require system || return 1
  printf '%s\t' "$1" | cliphist decode | wl-copy
  printf '%s\t' "$1" | cliphist delete
  paste_string
}

add_favorite() {
  local encoded=""
  encoded="$(printf '%s\t' "$1" | cliphist decode | base64 -w 0)"
  [[ -n "${encoded}" ]] || return 1
  mkdir -p "${favorites_file%/*}"
  grep -Fxqs -- "${encoded}" "${favorites_file}" || printf '%s\n' "${encoded}" >>"${favorites_file}"
}

cached_image() {
  local image=""
  image="$(hypr_runtime_subdir hypr/cliphist)/$1" || return 1
  [[ -s "${image}" ]] || printf '%s\t' "$1" | cliphist decode >"${image}" || { rm -f "${image}"; return 1; }
  printf '%s\n' "${image}"
}

decoded_image() {
  local image=""
  image="$(mktemp "$(hypr_runtime_subdir hypr)/cliphist.XXXXXX")" &&
    printf '%s\t' "$1" | cliphist decode >"${image}" && printf '%s\n' "${image}" && return
  rm -f "${image}"
  dunstify -t "${NOTIFY_MS}" -i dialog-error "$2 Error" "Failed to decode the clipboard image."
  return 1
}

ocr_entry() {
  local image="" ocr_image="" text=""
  local -a languages=()
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/capture/ocr.common.bash" || return 1
  hypr_ocr_prepare_languages languages || {
    dunstify -t "${OCR_ERROR_NOTIFY_MS}" -i dialog-error "OCR Error" "${HYPR_OCR_ERROR}"
    return 1
  }
  # Clipboard images arrive at an arbitrary rotation, so this path also asks for
  # orientation and script detection; a fresh screen grab never needs it.
  languages+=("osd")
  image="$(decoded_image "$1" OCR)" || return 1
  hypr_ocr_preprocess_into ocr_image "${image}" image
  if text="$(hypr_ocr_recognize "${ocr_image}" "$(hypr_ocr_language_argument languages)")"; then
    printf '%s' "${text}" | wl-copy
    dunstify -t "${NOTIFY_LONG_MS}" -i "${image}" "OCR" "${#text} symbols recognized\n$(hypr_ocr_language_summary languages)"
  else
    dunstify -t "${NOTIFY_LONG_MS}" -i dialog-error "OCR Error" "Text recognition failed."
  fi
  rm -f "${image}" "${HYPR_OCR_TEMP_IMAGE}"
}

qr_entry() {
  local image="" text=""
  command -v zbarimg >/dev/null || {
    dunstify -t "${NOTIFY_LONG_MS}" -i dialog-error "QR Error" "zbarimg is not installed."
    return 1
  }
  image="$(decoded_image "$1" QR)" || return 1
  if text="$(zbarimg --quiet --oneshot --raw "${image}" 2>/dev/null)" && [[ -n "${text}" ]]; then
    # QR codes routinely carry secrets such as otpauth:// URIs, so the decoded
    # value is copied as sensitive and never lands in clipboard history
    printf '%s' "${text}" | wl-copy --sensitive
    dunstify -t "${NOTIFY_LONG_MS}" -i "${image}" "QR" "Successfully recognized and copied to clipboard."
  else
    dunstify -t "${NOTIFY_MS}" -i dialog-error "QR Error" "No QR code recognized."
  fi
  rm -f "${image}"
}

action="${1:-}" id="${2:-}"
[[ "${action}" =~ ^--(panel-json|wipe)$ || "${id}" =~ ^[1-9][0-9]*$ ]] || action=""
case "${action}" in
  --panel-json) panel_json ;;
  --panel-copy) copy_entry "${id}" ;;
  --panel-delete) printf '%s\t' "${id}" | cliphist delete ;;
  --panel-image) cached_image "${id}" ;;
  --panel-fav-add) add_favorite "${id}" ;;
  --panel-fav-copy) sed -n "${id}{p;q}" "${favorites_file}" | base64 --decode | wl-copy ;;
  --panel-fav-remove) sed -i "${id}d" "${favorites_file}" ;;
  --scan-image) ocr_entry "${id}" ;;
  --scan-qr) qr_entry "${id}" ;;
  --wipe) cliphist wipe && dunstify -t "${NOTIFY_MS}" -i edit-clear "Clipboard history cleared." ;;
  *)
    printf 'cliphist: invalid call: %s\n' "$*" >&2
    exit 2
    ;;
esac
