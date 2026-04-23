#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/capture/capture.select.bash"

USAGE() {
  cat <<"USAGE"

	Usage: $(basename "$0") [option] [destination]
	Options:
		p       Print all outputs
		smart   Smart selection (auto-detects windows, prevents tiny screenshots)
		area    Manual area selection
		area-freeze  Manual area selection with frozen screen
		m       Screenshot focused monitor
		w       Window selection (choose from visible windows)
		sc      Use tesseract to scan image, then add to clipboard

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

if [[ "${mode}" == "smart" && ( "${destination_arg}" == "clipboard" || "${destination_arg}" == "save" ) ]]; then
  smart_destination="${destination_arg}"
  save_dir_arg="${3:-}"
fi

save_dir="${save_dir_arg:-${XDG_SCREENSHOTS_DIR:-$XDG_PICTURES_DIR/Screenshots}}"
save_file=$(date +'%y%m%d_%Hh%Mm%Ss_screenshot.png')
annotation_tool="satty"
annotation_args=(
  "--filename" "${temp_screenshot}"
  "--output-filename" "${save_dir}/${save_file}"
  "--copy-command" "wl-copy"
  "--actions-on-enter" "save-to-clipboard"
  "--save-after-copy"
  "--resize" "smart"
)
tesseract_default_language=("eng")
tesseract_languages=("${SCREENSHOT_OCR_TESSERACT_LANGUAGES[@]:-${tesseract_default_language[@]}}")
tesseract_languages+=("osd")

mkdir -p "$save_dir"

# Add any additional annotation arguments
[[ -n "${SCREENSHOT_ANNOTATION_ARGS[*]}" ]] && annotation_args+=("${SCREENSHOT_ANNOTATION_ARGS[@]}")

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

# screenshot function, globbing was difficult to read and maintain
take_screenshot() {
  local mode="$1"
  shift
  local extra_args=("$@")

  capture_then_annotate grimblast_capture "${extra_args[@]}" save "$mode" "$temp_screenshot"
}

ocr_screenshot() {
  local mode="$1"
  shift
  local extra_args=("$@")
  local pkg=""
  local tesseract_language=""
  local tesseract_languages_body="Languages used"
  local tesseract_package_prefix="tesseract-data-"
  local -a tesseract_packages=()
  local tesseract_languages_prepared=""
  local tesseract_output=""

  if grimblast_capture "${extra_args[@]}" save "$mode" "$temp_screenshot"; then
    if pkg_installed imagemagick; then
      magick "${temp_screenshot}" \
        -colorspace gray \
        -contrast-stretch 0 \
        -level 15%,85% \
        -resize 400% \
        -sharpen 0x1 \
        -auto-threshold triangle \
        -morphology close diamond:1 \
        -deskew 40% \
        "${temp_screenshot}"
    else
      screenshot_notify 5000 "dialog-warning" "OCR: imagemagick is not installed, recognition accuracy is reduced"
    fi
    tesseract_packages=("${tesseract_languages[@]/#/$tesseract_package_prefix}")
    tesseract_packages+=("tesseract")
    for pkg in "${tesseract_packages[@]}"; do
      if ! pkg_installed "${pkg}"; then
        screenshot_notify 5000 "dialog-error" "OCR: required package is not installed" " ${pkg}"
        rm -f "${temp_screenshot}"
        return 1
      fi
    done
    tesseract_languages_prepared=$(
      IFS=+
      printf '%s' "${tesseract_languages[*]}"
    )
    for tesseract_language in "${tesseract_languages[@]}"; do
      tesseract_languages_body+=$'\n '"${tesseract_language}"
    done
    if ! tesseract_output=$(
      tesseract \
        --psm 6 \
        --oem 3 \
        -l "${tesseract_languages_prepared}" \
        "${temp_screenshot}" \
        stdout \
        2>/dev/null
    ); then
      screenshot_notify 5000 "dialog-error" "OCR: text recognition failed"
      rm -f "${temp_screenshot}"
      return 1
    fi
    printf "%s" "$tesseract_output" | wl-copy
    screenshot_notify 5000 "${temp_screenshot}" "OCR: ${#tesseract_output} symbols recognized" "${tesseract_languages_body}"
    rm -f "${temp_screenshot}"
  else
    screenshot_notify 5000 "dialog-error" "OCR: screenshot error"
    return 1
  fi
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
  sc) #? 󱉶 Use 'tesseract' to scan image then add to clipboard
    ocr_screenshot "area" "--freeze"
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
