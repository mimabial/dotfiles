#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/capture/capture.select.bash"

USAGE() {
  cat <<"USAGE"

	Usage: $(basename "$0") [option] [destination]
	Options:
		p       Print all outputs
		s       Select area or window to screenshot
		sf      Select area or window with frozen screen (grimblast)
		smart   Smart selection (auto-detects windows, prevents tiny screenshots)
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

if [[ -z "${XDG_PICTURES_DIR}" ]]; then
  XDG_PICTURES_DIR="$HOME/Pictures"
fi

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
  if ! command -v satty >/dev/null 2>&1; then
    dunstify -a "Screenshot" -t 5000 -i "dialog-error" "Screenshot Error" "Satty is not installed"
    return 1
  fi
  "${annotation_tool}" "${annotation_args[@]}"
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

  if [[ "${selection}" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
    if (( ${BASH_REMATCH[3]} * ${BASH_REMATCH[4]} < 20 )); then
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
        dunstify -a "Screenshot" -t 5000 -i "dialog-error" "Screenshot Error" "Failed to take screenshot"
        return 1
      fi
      dunstify -a "Screenshot" -t 3000 "Copied to clipboard" -i "camera-photo"
      ;;
    save)
      if ! grimblast_capture_geometry "save" "${selection}" "${save_dir}/${save_file}"; then
        dunstify -a "Screenshot" -t 5000 -i "dialog-error" "Screenshot Error" "Failed to save screenshot"
        return 1
      fi
      ;;
    *)
      if ! grimblast_capture_geometry "save" "${selection}" "${temp_screenshot}"; then
        dunstify -a "Screenshot" -t 5000 -i "dialog-error" "Screenshot Error" "Failed to take screenshot"
        return 1
      fi
      if ! run_annotation; then
        dunstify -a "Screenshot" -t 5000 -i "dialog-error" "Screenshot Error" "Failed to open annotation tool"
        return 1
      fi
      ;;
  esac
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
  local mode=$1
  shift
  local extra_args=("$@")

  if grimblast_capture "${extra_args[@]}" save "$mode" "$temp_screenshot"; then
    if ! run_annotation; then
      dunstify -a "Screenshot" -t 5000 -i "dialog-error" "Screenshot Error" "Failed to open annotation tool"
      return 1
    fi
  else
    dunstify -a "Screenshot" -t 5000 -i "dialog-error" "Screenshot Error" "Failed to take screenshot"
    return 1
  fi
}

ocr_screenshot() {
  local mode=$1
  shift
  local extra_args=("$@")

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
      dunstify -a "Screenshot" -t 5000 "OCR: imagemagick is not installed, recognition accuracy is reduced" -i "dialog-warning"
    fi
    tesseract_package_prefix="tesseract-data-"
    tesseract_packages=("${tesseract_languages[@]/#/$tesseract_package_prefix}")
    tesseract_packages+=("tesseract")
    for pkg in "${tesseract_packages[@]}"; do
      if ! pkg_installed "${pkg}"; then
        dunstify -a "Screenshot" -t 5000 "$(echo -e "OCR: required package is not installed\n ${pkg}")" -i "dialog-error"
        return 1
      fi
    done
    tesseract_languages_prepared=$(
      IFS=+
      echo "${tesseract_languages[*]}"
    )
    tesseract_output=$(
      tesseract \
        --psm 6 \
        --oem 3 \
        -l "${tesseract_languages_prepared}" \
        "${temp_screenshot}" \
        stdout
      2>/dev/null
    )
    printf "%s" "$tesseract_output" | wl-copy
    dunstify -a "Screenshot" -t 5000 "$(echo -e "OCR: ${#tesseract_output} symbols recognized\n\nLanguages used ${tesseract_languages[@]/#/'\n '}")" -i "${temp_screenshot}"
    rm -f "${temp_screenshot}"
  else
    dunstify -a "Screenshot" -t 5000 "OCR: screenshot error" -i "dialog-error"
    return 1
  fi
}

trap 'cleanup_temp_screenshot "$?"' EXIT

case "${mode}" in
  p) # print all outputs
    take_screenshot "screen"
    ;;
  s) # drag to manually snip an area / click on a window to print it
    take_screenshot "area"
    ;;
  sf) # frozen screen, drag to manually snip an area / click on a window to print it
    take_screenshot "area" "--freeze"
    ;;
  smart) # smart selection with wayfreeze and auto window detection
    smart_screenshot "${smart_destination:-$2}"
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
  dunstify -a "Screenshot" -t 5000 -i "${save_dir}/${save_file}" "saved in ${save_dir}"
fi
