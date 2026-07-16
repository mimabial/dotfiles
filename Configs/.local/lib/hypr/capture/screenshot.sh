#!/usr/bin/env bash
#
# screenshot.sh — Capture screenshots and OCR from the Hyprland session.
#
# Usage: screenshot.sh [mode] [destination]
# Depends on: hyprshell, grimblast, satty, slurp, grim, wl-copy
#
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/capture/capture.select.bash"

USAGE() {
  cat <<USAGE

	Usage: $(basename "$0") [option] [destination]
	Options:
		p       Print all outputs
		smart   Smart selection (auto-detects windows, prevents tiny screenshots)
		area    Manual area selection
		area-freeze  Manual area selection with frozen screen
		m       Screenshot focused monitor
		w       Window selection (choose from visible windows)
		ocr     Extract text from selected area and copy it to clipboard
		text    Alias for ocr
		sc      Legacy alias for ocr area clipboard

	OCR:
		ocr [area|smart|window|monitor|screen] [clipboard|save|both|stdout]
		SCREENSHOT_OCR_LANGS="eng+fra" selects OCR languages.

	Destinations (optional for smart mode):
		clipboard    Copy to clipboard only (no annotation)
		save         Save directly without annotation

USAGE
}

cleanup_temp_screenshot() {
  local exit_code="${1:-$?}"
  if [[ -n "${temp_screenshot:-}" && -f "${temp_screenshot}" ]]; then
    rm -f "${temp_screenshot}" || true
  fi
  if [[ -n "${temp_ocr_image:-}" && -f "${temp_ocr_image}" ]]; then
    rm -f "${temp_ocr_image}" || true
  fi
  return "${exit_code}"
}

# Create secure temporary file
temp_screenshot=$(mktemp -t screenshot_XXXXXX.png)

XDG_PICTURES_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"

grimblast_script="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/capture/grimblast.sh"
mode="${1:-}"
destination_arg="${2:-}"
save_dir_arg="${2:-}"
smart_destination=""

case "${mode}" in
  smart)
    if [[ "${destination_arg}" == "clipboard" || "${destination_arg}" == "save" ]]; then
      smart_destination="${destination_arg}"
      save_dir_arg="${3:-}"
    fi
    ;;
  ocr | text)
    save_dir_arg="${4:-}"
    ;;
  ocr-* | text-* | sc)
    save_dir_arg="${3:-}"
    ;;
esac

save_dir="${save_dir_arg:-${XDG_SCREENSHOTS_DIR:-$XDG_PICTURES_DIR/Screenshots}}"
save_file=$(date +'%y%m%d_%Hh%Mm%Ss_screenshot.png')
save_text_file=$(date +'%y%m%d_%Hh%Mm%Ss_ocr.txt')
annotation_tool="satty"
annotation_args=(
  "--filename" "${temp_screenshot}"
  "--output-filename" "${save_dir}/${save_file}"
  "--copy-command" "wl-copy"
  "--actions-on-enter" "save-to-clipboard"
  "--save-after-copy"
  "--resize" "smart"
)

mkdir -p "$save_dir"

# Add any additional annotation arguments
[[ -n "${SCREENSHOT_ANNOTATION_ARGS[*]:-}" ]] && annotation_args+=("${SCREENSHOT_ANNOTATION_ARGS[@]}")

run_annotation() {
  if ! command -v "${annotation_tool}" >/dev/null 2>&1; then
    screenshot_error_notify "${annotation_tool} is not installed"
    return 1
  fi
  "${annotation_tool}" "${annotation_args[@]}"
}

screenshot_notify() {
  local timeout="$1"
  local icon="$2"
  local summary="$3"
  local body="${4:-}"

  if [[ -n "${body}" ]]; then
    dunstify -a "Screenshot" -t "${timeout}" -i "${icon}" "${summary}" "${body}"
  else
    dunstify -a "Screenshot" -t "${timeout}" -i "${icon}" "${summary}"
  fi
}

screenshot_error_notify() {
  screenshot_notify 5000 "dialog-error" "Screenshot Error" "$1"
}

grimblast_capture() {
  "${grimblast_script}" "$@"
}

grimblast_capture_geometry() {
  local action="$1"
  local selection="$2"
  local output_file="${3:-}"
  local args=(--geometry "${selection}" "${action}" "area")

  if [[ -n "${output_file}" ]]; then
    args+=("${output_file}")
  fi

  grimblast_capture "${args[@]}"
}

capture_then_annotate() {
  "$@" || {
    screenshot_error_notify "Failed to take screenshot"
    return 1
  }

  run_annotation || {
    screenshot_error_notify "Failed to open annotation tool"
    return 1
  }
}

get_rectangles() {
  capture_active_workspace_rectangles
}

select_geometry_from_rectangles() {
  local rectangles="$1"
  shift
  local selection=""
  local freeze_pid=""

  freeze_pid="$(capture_start_freeze 0.1)"
  selection="$(printf '%s\n' "${rectangles}" | slurp "$@" 2>/dev/null)"
  capture_stop_freeze "${freeze_pid}"
  [[ -n "${selection}" ]] || return 1
  printf '%s\n' "${selection}"
}

expand_tiny_selection_to_rectangle() {
  local selection="$1"
  local rectangles="$2"
  local rect=""

  if [[ "${selection}" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
    if (( BASH_REMATCH[3] * BASH_REMATCH[4] < 20 )); then
      local click_x="${BASH_REMATCH[1]}"
      local click_y="${BASH_REMATCH[2]}"

      while IFS= read -r rect; do
        if [[ "$rect" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+) ]]; then
          local rect_x="${BASH_REMATCH[1]}"
          local rect_y="${BASH_REMATCH[2]}"
          local rect_width="${BASH_REMATCH[3]}"
          local rect_height="${BASH_REMATCH[4]}"

          if (( click_x >= rect_x && click_x < rect_x+rect_width && click_y >= rect_y && click_y < rect_y+rect_height )); then
            selection="${rect_x},${rect_y} ${rect_width}x${rect_height}"
            break
          fi
        fi
      done <<<"${rectangles}"
    fi
  fi

  printf '%s\n' "${selection}"
}

capture_selected_geometry() {
  local selection="$1"
  local destination="${2:-annotate}"

  case "${destination}" in
    clipboard)
      if ! grimblast_capture_geometry "copy" "${selection}"; then
        screenshot_error_notify "Failed to take screenshot"
        return 1
      fi
      screenshot_notify 3000 "camera-photo" "Copied to clipboard"
      ;;
    save)
      if ! grimblast_capture_geometry "save" "${selection}" "${save_dir}/${save_file}"; then
        screenshot_error_notify "Failed to save screenshot"
        return 1
      fi
      ;;
    *)
      capture_then_annotate grimblast_capture_geometry "save" "${selection}" "${temp_screenshot}"
      ;;
  esac
}

manual_area_screenshot() {
  local freeze_selection="${1:-0}"
  local -a grimblast_args=()

  [[ "${freeze_selection}" -eq 1 ]] && grimblast_args+=(--freeze)
  capture_then_annotate grimblast_capture "${grimblast_args[@]}" save area "${temp_screenshot}"
}

# Smart screenshot with frozen screen and smart detection
smart_screenshot() {
  local destination="$1"
  local rectangles=""
  local selection=""

  rectangles="$(get_rectangles)"
  selection="$(select_geometry_from_rectangles "${rectangles}")" || return 0
  selection="$(expand_tiny_selection_to_rectangle "${selection}" "${rectangles}")"

  capture_selected_geometry "${selection}" "${destination}"
}

window_screenshot() {
  local rectangles=""
  local selection=""

  rectangles="$(get_rectangles)"
  selection="$(select_geometry_from_rectangles "${rectangles}" -r)" || return 0
  capture_selected_geometry "${selection}" "annotate"
}

take_screenshot() {
  local mode="$1"
  shift
  local extra_args=("$@")

  capture_then_annotate grimblast_capture "${extra_args[@]}" save "$mode" "$temp_screenshot"
}

ocr_screenshot() {
  local subject="${1:-area}"
  local destination="${2:-clipboard}"
  local ocr_image="${temp_screenshot}"
  local text_file="${save_dir}/${save_text_file}"
  local tesseract_languages_prepared=""
  local tesseract_languages_body="Languages used"
  local tesseract_output=""
  local language=""
  local -a tesseract_languages=()

  ocr_capture_subject "${subject}" || {
    screenshot_notify 5000 "dialog-error" "OCR: screenshot error"
    return 1
  }

  ocr_prepare_languages tesseract_languages || return 1
  tesseract_languages_prepared="$(
    IFS=+
    printf '%s' "${tesseract_languages[*]}"
  )"
  for language in "${tesseract_languages[@]}"; do
    tesseract_languages_body+=$'\n '"${language}"
  done

  ocr_image="$(ocr_preprocess_image "${temp_screenshot}")"

  if ! tesseract_output=$(
    tesseract \
      "${ocr_image}" \
      stdout \
      --oem "${SCREENSHOT_OCR_OEM:-1}" \
      --psm "${SCREENSHOT_OCR_PSM:-6}" \
      --dpi "${SCREENSHOT_OCR_DPI:-300}" \
      -l "${tesseract_languages_prepared}" \
      -c preserve_interword_spaces=1 \
      2>/dev/null
  ); then
    screenshot_notify 5000 "dialog-error" "OCR: text recognition failed"
    return 1
  fi

  if [[ -z "${tesseract_output//[[:space:]]/}" ]]; then
    screenshot_notify 5000 "${temp_screenshot}" "OCR: no text found" "${tesseract_languages_body}"
    return 1
  fi

  ocr_emit_text "${destination}" "${tesseract_output}" "${text_file}" || return 1
  ocr_notify_success "${destination}" "${text_file}" "${#tesseract_output}" "${tesseract_languages_body}"
}

ocr_capture_subject() {
  local subject="$1"
  local rectangles=""
  local selection=""

  case "${subject}" in
    area | region | selection)
      grimblast_capture --freeze save area "${temp_screenshot}"
      ;;
    smart)
      rectangles="$(get_rectangles)"
      selection="$(select_geometry_from_rectangles "${rectangles}")" || return 1
      selection="$(expand_tiny_selection_to_rectangle "${selection}" "${rectangles}")"
      grimblast_capture_geometry "save" "${selection}" "${temp_screenshot}"
      ;;
    window | w)
      rectangles="$(get_rectangles)"
      selection="$(select_geometry_from_rectangles "${rectangles}" -r)" || return 1
      grimblast_capture_geometry "save" "${selection}" "${temp_screenshot}"
      ;;
    monitor | output | m)
      grimblast_capture save output "${temp_screenshot}"
      ;;
    screen | fullscreen | p)
      grimblast_capture save screen "${temp_screenshot}"
      ;;
    *)
      screenshot_error_notify "OCR: invalid subject '${subject}'"
      return 1
      ;;
  esac
}

ocr_configured_languages() {
  local raw=""
  local -a languages=()

  if declare -p SCREENSHOT_OCR_TESSERACT_LANGUAGES >/dev/null 2>&1; then
    eval 'languages=("${SCREENSHOT_OCR_TESSERACT_LANGUAGES[@]}")'
  else
    raw="${SCREENSHOT_OCR_LANGS:-${OMARCHY_OCR_LANGS:-eng}}"
    raw="${raw//+/ }"
    raw="${raw//,/ }"
    # shellcheck disable=SC2206
    languages=(${raw})
  fi

  printf '%s\n' "${languages[@]}" | awk 'NF && !seen[$0]++'
}

ocr_prepare_languages() {
  local -n out_languages="$1"
  local language=""
  local installed=""
  local missing=""

  if ! command -v tesseract >/dev/null 2>&1; then
    screenshot_notify 5000 "dialog-error" "OCR: tesseract is not installed"
    return 1
  fi

  installed="$(tesseract --list-langs 2>/dev/null | tail -n +2)"
  mapfile -t out_languages < <(ocr_configured_languages)
  [[ "${#out_languages[@]}" -gt 0 ]] || out_languages=("eng")

  for language in "${out_languages[@]}"; do
    if ! grep -Fxq "${language}" <<<"${installed}"; then
      missing+="${missing:+, }${language}"
    fi
  done

  if [[ -n "${missing}" ]]; then
    screenshot_notify 7000 "dialog-error" "OCR: missing tesseract language data" "Missing: ${missing}"$'\n'"Installed: ${installed//$'\n'/, }"
    return 1
  fi
}

ocr_preprocess_image() {
  local input="$1"

  if [[ "${SCREENSHOT_OCR_PREPROCESS:-1}" != "1" ]]; then
    printf '%s\n' "${input}"
    return 0
  fi

  if ! command -v magick >/dev/null 2>&1; then
    screenshot_notify 5000 "dialog-warning" "OCR: imagemagick is not installed, recognition accuracy is reduced"
    printf '%s\n' "${input}"
    return 0
  fi

  temp_ocr_image="$(mktemp -t screenshot_ocr_XXXXXX.png)"
  if magick "${input}" \
    -colorspace gray \
    -contrast-stretch 0 \
    -resize 300% \
    -sharpen 0x1 \
    -deskew 40% \
    "${temp_ocr_image}"; then
    printf '%s\n' "${temp_ocr_image}"
  else
    rm -f "${temp_ocr_image}"
    temp_ocr_image=""
    screenshot_notify 5000 "dialog-warning" "OCR: image preprocessing failed, using original screenshot"
    printf '%s\n' "${input}"
  fi
}

ocr_emit_text() {
  local destination="$1"
  local text="$2"
  local text_file="$3"

  case "${destination}" in
    "" | clipboard | copy)
      printf '%s' "${text}" | wl-copy
      ;;
    save | file)
      printf '%s\n' "${text}" >"${text_file}"
      ;;
    both | copy-save | save-copy)
      printf '%s' "${text}" | wl-copy
      printf '%s\n' "${text}" >"${text_file}"
      ;;
    stdout | print)
      printf '%s\n' "${text}"
      ;;
    *)
      screenshot_error_notify "OCR: invalid destination '${destination}'"
      return 1
      ;;
  esac
}

ocr_notify_success() {
  local destination="$1"
  local text_file="$2"
  local symbol_count="$3"
  local language_body="$4"
  local summary="OCR: ${symbol_count} symbols recognized"
  local body="${language_body}"

  case "${destination}" in
    "" | clipboard | copy)
      body="Copied to clipboard"$'\n'"${body}"
      ;;
    save | file)
      body="Saved to ${text_file}"$'\n'"${body}"
      ;;
    both | copy-save | save-copy)
      body="Copied to clipboard"$'\n'"Saved to ${text_file}"$'\n'"${body}"
      ;;
    stdout | print)
      return 0
      ;;
  esac

  screenshot_notify 5000 "${temp_screenshot}" "${summary}" "${body}"
}

trap 'cleanup_temp_screenshot "$?"' EXIT

case "${mode}" in
  p) # print all outputs
    take_screenshot "screen"
    ;;
  smart) # smart selection with wayfreeze and auto window detection
    smart_screenshot "${smart_destination:-$2}"
    ;;
  area) # manual area selection
    manual_area_screenshot 0
    ;;
  area-freeze) # manual area selection with frozen screen
    manual_area_screenshot 1
    ;;
  w) # window selection with frozen screen
    window_screenshot
    ;;
  m) # print focused monitor
    take_screenshot "output"
    ;;
  ocr | text) #? 󱉶 Extract text from a screenshot
    ocr_screenshot "${2:-area}" "${3:-clipboard}"
    ;;
  ocr-area | text-area | sc) #? 󱉶 Extract text from selected area
    ocr_screenshot "area" "${2:-clipboard}"
    ;;
  ocr-smart | text-smart)
    ocr_screenshot "smart" "${2:-clipboard}"
    ;;
  ocr-window | text-window)
    ocr_screenshot "window" "${2:-clipboard}"
    ;;
  ocr-monitor | text-monitor)
    ocr_screenshot "monitor" "${2:-clipboard}"
    ;;
  ocr-screen | text-screen)
    ocr_screenshot "screen" "${2:-clipboard}"
    ;;
  *) # invalid option or default to smart
    if [[ -z "${mode}" ]]; then
      smart_screenshot "${smart_destination}"
    else
      USAGE
    fi
    ;;
esac

if [ -f "${save_dir}/${save_file}" ]; then
  screenshot_notify 5000 "${save_dir}/${save_file}" "saved in ${save_dir}"
fi
