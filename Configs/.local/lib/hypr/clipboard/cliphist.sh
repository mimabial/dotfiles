#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_help_guard "Usage: hyprshell clipboard/cliphist --panel-json | --wipe | --panel-{copy,delete,image,fav-add} ID | --panel-fav-{copy,remove} N | --scan-{image,qr} ID" "$@"

favorites_file="${XDG_CACHE_HOME:-$HOME/.cache}/landing/cliphist_favorites"
OCR_ERROR_NOTIFY_MS=7000

run_cliphist_for_entry() {
  printf '%s\t' "$2" | cliphist "$1"
}

emit_clipboard_panel_json() {
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

move_entry_to_newest_and_paste() {
  local entry=""
  hypr_runtime_require system || return 1
  entry="$(decode_entry_to_temporary_file "$1" "Clipboard Error")" || return 1
  { rm -f "${entry}"; wl-copy; } <"${entry}" || return 1
  run_cliphist_for_entry delete "$1"
  paste_clipboard
}

add_favorite() {
  local encoded=""
  encoded="$(run_cliphist_for_entry decode "$1" | base64 -w 0)"
  [[ -n "${encoded}" ]] || return 1
  mkdir -p "${favorites_file%/*}"
  grep -Fxqs -- "${encoded}" "${favorites_file}" || printf '%s\n' "${encoded}" >>"${favorites_file}"
}

cache_entry_image() {
  local image=""
  image="$(hypr_ensure_runtime_subdir hypr/cliphist)/$1" || return 1
  [[ -s "${image}" ]] || run_cliphist_for_entry decode "$1" >"${image}" || { rm -f "${image}"; return 1; }
  printf '%s\n' "${image}"
}

decode_entry_to_temporary_file() {
  local id="$1" error_title="$2" image=""
  image="$(mktemp "$(hypr_ensure_runtime_subdir hypr)/cliphist.XXXXXX")" &&
    run_cliphist_for_entry decode "${id}" >"${image}" && printf '%s\n' "${image}" && return
  rm -f "${image}"
  dunstify -t "${NOTIFY_MS}" -i dialog-error "${error_title}" "Failed to decode the clipboard entry."
  return 1
}

recognize_entry_text() {
  local image="" ocr_image="" ocr_temp_image="" ocr_failure="" preprocess_warning="" text=""
  local -a languages=()
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/capture/lib/text-recognition.bash" || return 1
  hypr_ocr_prepare_languages languages ocr_failure || {
    dunstify -t "${OCR_ERROR_NOTIFY_MS}" -i dialog-error "OCR Error" "${ocr_failure}"
    return 1
  }
  # Clipboard images arrive at an arbitrary rotation, so this path also asks for
  # orientation and script detection; a fresh screen grab never needs it.
  languages+=("osd")
  image="$(decode_entry_to_temporary_file "$1" "OCR Error")" || return 1
  hypr_ocr_preprocess_best_effort_into ocr_image ocr_temp_image preprocess_warning "${image}" image
  if text="$(hypr_ocr_recognize "${ocr_image}" "$(hypr_ocr_language_argument languages)")"; then
    printf '%s' "${text}" | wl-copy
    dunstify -t "${NOTIFY_LONG_MS}" -i "${image}" "OCR" "${#text} symbols recognized\n$(hypr_ocr_language_summary languages)"
  else
    dunstify -t "${NOTIFY_LONG_MS}" -i dialog-error "OCR Error" "Text recognition failed."
  fi
  rm -f "${image}" "${ocr_temp_image}"
}

recognize_entry_qr_code() {
  local image="" text=""
  command -v zbarimg >/dev/null || {
    dunstify -t "${NOTIFY_LONG_MS}" -i dialog-error "QR Error" "zbarimg is not installed."
    return 1
  }
  image="$(decode_entry_to_temporary_file "$1" "QR Error")" || return 1
  if text="$(zbarimg --quiet --oneshot --raw -Sdisable -Sqrcode.enable "${image}" 2>/dev/null)" && [[ -n "${text}" ]]; then
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
  --panel-json) emit_clipboard_panel_json ;;
  --panel-copy) move_entry_to_newest_and_paste "${id}" ;;
  --panel-delete) run_cliphist_for_entry delete "${id}" ;;
  --panel-image) cache_entry_image "${id}" ;;
  --panel-fav-add) add_favorite "${id}" ;;
  --panel-fav-copy) sed -n "${id}{p;q}" "${favorites_file}" | base64 --decode | wl-copy ;;
  --panel-fav-remove) sed -i "${id}d" "${favorites_file}" ;;
  --scan-image) recognize_entry_text "${id}" ;;
  --scan-qr) recognize_entry_qr_code "${id}" ;;
  --wipe) cliphist wipe && dunstify -t "${NOTIFY_MS}" -i edit-clear "Clipboard history cleared." ;;
  *)
    printf 'cliphist: invalid call: %s\n' "$*" >&2
    exit 2
    ;;
esac
