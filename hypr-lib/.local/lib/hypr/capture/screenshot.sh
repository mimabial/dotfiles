#!/usr/bin/env bash

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

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

SCREENSHOT_POST_COMMAND+=(
)

SCREENSHOT_PRE_COMMAND+=(
)

pre_cmd() {
  for cmd in "${SCREENSHOT_PRE_COMMAND[@]}"; do
    eval "$cmd"
  done
  trap 'post_cmd' EXIT
}

post_cmd() {
  for cmd in "${SCREENSHOT_POST_COMMAND[@]}"; do
    eval "$cmd"
  done
}

# Create secure temporary file
temp_screenshot=$(mktemp -t screenshot_XXXXXX.png)

if [ -z "$XDG_PICTURES_DIR" ]; then
  XDG_PICTURES_DIR="$HOME/Pictures"
fi

confDir="${confDir:-$XDG_CONFIG_HOME}"
save_dir="${2:-$XDG_PICTURES_DIR/Screenshots}"
save_file=$(date +'%y%m%d_%Hh%Mm%Ss_screenshot.png')
annotation_tool=${SCREENSHOT_ANNOTATION_TOOL}
annotation_args=("-o" "${save_dir}/${save_file}" "-f" "${temp_screenshot}")
tesseract_default_language=("eng")
tesseract_languages=("${SCREENSHOT_OCR_TESSERACT_LANGUAGES[@]:-${tesseract_default_language[@]}}")
tesseract_languages+=("osd")

if [[ -z "$annotation_tool" ]]; then
  pkg_installed "swappy" && annotation_tool="swappy"
  pkg_installed "satty" && annotation_tool="satty"
fi
mkdir -p "$save_dir"

# Fixes the issue where the annotation tool doesn't save the file in the correct directory
if [[ "$annotation_tool" == "swappy" ]]; then
  swpy_dir="${confDir}/swappy"
  mkdir -p "$swpy_dir"
  echo -e "[Default]\nsave_dir=$save_dir\nsave_filename_format=$save_file" >"${swpy_dir}"/config
fi

if [[ "$annotation_tool" == "satty" ]]; then
  annotation_args+=("--copy-command" "wl-copy")
fi

# Add any additional annotation arguments
[[ -n "${SCREENSHOT_ANNOTATION_ARGS[*]}" ]] && annotation_args+=("${SCREENSHOT_ANNOTATION_ARGS[@]}")

# Get rectangles for smart selection
get_rectangles() {
  local active_workspace=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .activeWorkspace.id')
  hyprctl monitors -j | jq -r --arg ws "$active_workspace" '.[] | select(.activeWorkspace.id == ($ws | tonumber)) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"'
  hyprctl clients -j | jq -r --arg ws "$active_workspace" '.[] | select(.workspace.id == ($ws | tonumber)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

# Smart screenshot with frozen screen and smart detection
smart_screenshot() {
  local destination="$1"
  local RECTS=$(get_rectangles)

  # Use slurp for selection with window rectangles
  local SELECTION=$(echo "$RECTS" | slurp 2>/dev/null)
  [ -z "$SELECTION" ] && return 0

  # Smart window detection: if selection is tiny (< 20px²), expand to window/monitor
  if [[ "$SELECTION" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
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
            SELECTION="${rect_x},${rect_y} ${rect_width}x${rect_height}"
            break
          fi
        fi
      done <<< "$RECTS"
    fi
  fi

  [ -z "$SELECTION" ] && return 0

  # Take screenshot with grim
  if [[ "$destination" == "clipboard" ]]; then
    grim -g "$SELECTION" - | wl-copy
    notify-send -a "Screenshot" "Copied to clipboard" -i "camera-photo"
  elif [[ "$destination" == "save" ]]; then
    grim -g "$SELECTION" "${save_dir}/${save_file}"
  else
    grim -g "$SELECTION" "$temp_screenshot"
    if ! "${annotation_tool}" "${annotation_args[@]}"; then
      notify-send -a "Screenshot" "Screenshot Error" "Failed to open annotation tool"
      return 1
    fi
  fi
}

# screenshot function, globbing was difficult to read and maintain
take_screenshot() {
  local mode=$1
  shift
  local extra_args=("$@")

  # execute grimblast with given args
  if "$LIB_DIR/hypr/capture/grimblast" "${extra_args[@]}" copysave "$mode" "$temp_screenshot"; then
    if ! "${annotation_tool}" "${annotation_args[@]}"; then
      notify-send -a "Screenshot" "Screenshot Error" "Failed to open annotation tool"
      return 1
    fi
  else
    notify-send -a "Screenshot" "Screenshot Error" "Failed to take screenshot"
    return 1
  fi
}

ocr_screenshot() {
  local mode=$1
  shift
  local extra_args=("$@")

  # execute grimblast with given args
  if "$LIB_DIR/hypr/capture/grimblast" "${extra_args[@]}" copysave "$mode" "$temp_screenshot"; then
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
      notify-send -a "Screenshot" "OCR: imagemagick is not installed, recognition accuracy is reduced" -e -i "dialog-warning"
    fi
    tesseract_package_prefix="tesseract-data-"
    tesseract_packages=("${tesseract_languages[@]/#/$tesseract_package_prefix}")
    tesseract_packages+=("tesseract")
    for pkg in "${tesseract_packages[@]}"; do
      if ! pkg_installed "${pkg}"; then
        notify-send -a "Screenshot" "$(echo -e "OCR: required package is not installed\n ${pkg}")" -e -i "dialog-error"
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
        -l ${tesseract_languages_prepared} \
        "${temp_screenshot}" \
        stdout
      2>/dev/null
    )
    printf "%s" "$tesseract_output" | wl-copy
    notify-send -a "Screenshot" "$(echo -e "OCR: ${#tesseract_output} symbols recognized\n\nLanguages used ${tesseract_languages[@]/#/'\n '}")" -i "${temp_screenshot}" -e
    rm -f "${temp_screenshot}"
  else
    notify-send -a "Screenshot" "OCR: screenshot error" -e -i "dialog-error"
    return 1
  fi
}

pre_cmd

case $1 in
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
    smart_screenshot "$2"
    ;;
  w) # window selection with frozen screen
    # Select from visible windows/monitors
    local SELECTION=$(get_rectangles | slurp -r 2>/dev/null)
    if [[ -n "$SELECTION" ]]; then
      grim -g "$SELECTION" "$temp_screenshot"
      "${annotation_tool}" "${annotation_args[@]}"
    fi
    ;;
  m) # print focused monitor
    take_screenshot "output"
    ;;
  sc) #? 󱉶 Use 'tesseract' to scan image then add to clipboard
    ocr_screenshot "area" "--freeze"
    ;;
  *) # invalid option or default to smart
    if [[ -z "$1" ]]; then
      smart_screenshot "$2"
    else
      USAGE
    fi
    ;;
esac

[ -f "${temp_screenshot}" ] && rm "${temp_screenshot}"

if [ -f "${save_dir}/${save_file}" ]; then
  notify-send -a "Screenshot" -i "${save_dir}/${save_file}" "saved in ${save_dir}"
fi
