#!/usr/bin/env bash
set -euo pipefail

hypr_lib="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
# shellcheck source=/dev/null
source "${hypr_lib}/capture/lib/selection.bash"
# shellcheck source=/dev/null
source "${hypr_lib}/capture/lib/text-recognition.bash"

usage() {
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
  if [[ -n "${ocr_temp_image}" && -f "${ocr_temp_image}" ]]; then
    rm -f "${ocr_temp_image}" || true
  fi
  return "${exit_code}"
}

temp_screenshot=$(mktemp -t screenshot_XXXXXX.png)
ocr_temp_image=""

XDG_PICTURES_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"

OCR_ERROR_NOTIFY_MS=7000
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
annotation_tool="swappy"
annotation_args=(
  "--file" "${temp_screenshot}"
  "--output-file" "${save_dir}/${save_file}"
)

mkdir -p "$save_dir"

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
  screenshot_notify "${NOTIFY_LONG_MS}" "dialog-error" "Screenshot Error" "$1"
}

focused_output_name() {
  hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'
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

capture_selected_geometry() {
  local selection="$1"
  local destination="${2:-annotate}"

  case "${destination}" in
    clipboard)
      if ! grim -g "${selection}" "${temp_screenshot}" || ! wl-copy --type image/png <"${temp_screenshot}"; then
        screenshot_error_notify "Failed to take screenshot"
        return 1
      fi
      screenshot_notify "${NOTIFY_MS}" "camera-photo" "Copied to clipboard"
      ;;
    save)
      if ! grim -g "${selection}" "${save_dir}/${save_file}"; then
        screenshot_error_notify "Failed to save screenshot"
        return 1
      fi
      ;;
    *)
      capture_then_annotate grim -g "${selection}" "${temp_screenshot}"
      ;;
  esac
}

smart_screenshot() {
  local destination="$1"
  local rectangles=""
  local selection=""

  rectangles="$(capture_active_workspace_rectangles)"
  selection="$(capture_select_geometry frozen "${rectangles}")" || return 0
  selection="$(capture_expand_tiny_selection "${selection}" "${rectangles}")"

  capture_selected_geometry "${selection}" "${destination}"
}

window_screenshot() {
  local rectangles=""
  local selection=""

  rectangles="$(capture_active_workspace_rectangles)"
  selection="$(capture_select_geometry frozen "${rectangles}" -r)" || return 0
  capture_selected_geometry "${selection}" "annotate"
}

area_screenshot() {
  local freeze="$1"
  local selection=""

  selection="$(capture_select_geometry "${freeze}" "$(capture_visible_workspace_rectangles)")" || return 0
  capture_selected_geometry "${selection}" "annotate"
}

source "${hypr_lib}/capture/lib/screenshot-ocr.bash"

trap 'cleanup_temp_screenshot "$?"' EXIT

case "${mode}" in
  p)
    capture_then_annotate grim "${temp_screenshot}"
    ;;
  smart)
    smart_screenshot "${smart_destination}"
    ;;
  area)
    area_screenshot live
    ;;
  area-freeze)
    area_screenshot frozen
    ;;
  w)
    window_screenshot
    ;;
  m)
    capture_then_annotate grim -o "$(focused_output_name)" "${temp_screenshot}"
    ;;
  ocr | text)
    ocr_screenshot "${2:-area}" "${3:-clipboard}"
    ;;
  ocr-area | text-area | sc)
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
  *)
    if [[ -z "${mode}" ]]; then
      smart_screenshot "${smart_destination}"
    else
      usage
    fi
    ;;
esac

if [ -f "${save_dir}/${save_file}" ]; then
  screenshot_notify "${NOTIFY_LONG_MS}" "${save_dir}/${save_file}" "saved in ${save_dir}"
fi
