#!/usr/bin/env bash

pkill -u "$USER" rofi && exit 0

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# define paths and files
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
favorites_file="${cache_dir}/landing/cliphist_favorites"
[ -f "$HOME/.cliphist_favorites" ] && favorites_file="$HOME/.cliphist_favorites"
cliphist_style="${ROFI_CLIPHIST_STYLE:-clipboard}"
cliphist_style="$(rofi_resolve_theme "${cliphist_style}")"
del_mode=false
action_delete="__action__:delete"
action_wipe="__action__:wipe"
action_copy="__action__:copy"
action_favorites="__action__:favorites"
action_options="__action__:options"
action_back="__action__:back"
action_image_history="__action__:image-history"
action_scan_image="__action__:scan-image"
action_scan_qr="__action__:scan-qr"

cliphist_action_id() {
  printf '%s\n' "${1%%$'\t'*}"
}

cliphist_dispatch_action() {
  case "$1" in
    "${action_copy}")
      "${0}" --copy
      ;;
    "${action_delete}")
      "${0}" --delete
      ;;
    "${action_wipe}")
      "${0}" --wipe
      ;;
    "${action_favorites}")
      "${0}" --favorites
      ;;
    "${action_options}")
      "${0}"
      ;;
    "${action_back}")
      main
      ;;
    "${action_image_history}")
      "${0}" --image-history
      ;;
    "${action_scan_image}")
      "${0}" --scan-image
      ;;
    "${action_scan_qr}")
      "${0}" --scan-qr
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

cliphist_action_from_exit_code() {
  case "$1" in
    10) printf '%s\n' "${action_copy}" ;;
    11) printf '%s\n' "${action_delete}" ;;
    12) printf '%s\n' "${action_favorites}" ;;
    13) printf '%s\n' "${action_wipe}" ;;
    14) printf '%s\n' "${action_options}" ;;
    15) printf '%s\n' "${action_image_history}" ;;
    16) printf '%s\n' "${action_scan_image}" ;;
    17) printf '%s\n' "${action_scan_qr}" ;;
    *) return 1 ;;
  esac
}

latest_image_history_entry() {
  local line=""

  while IFS= read -r line; do
    [[ "${line}" =~ ^[0-9]+[[:space:]]+\<meta[[:space:]]http-equiv= ]] && continue
    if [[ "${line}" =~ ^[0-9]+[[:space:]]+(\[\[[[:space:]])?binary.*(jpg|jpeg|png|bmp) ]]; then
      printf '%s\n' "${line}"
      return 0
    fi
  done < <(cliphist list)

  return 1
}

# process clipboard selections for multi-select mode
process_selections() {
  local first_action=""

  if [ true != "${del_mode}" ]; then
    # Read the entire input into an array
    mapfile -t lines #! Not POSIX compliant
    # Get the total number of lines
    total_lines=${#lines[@]}
    first_action="$(cliphist_action_id "${lines[0]:-}")"

    # handle special commands
    if cliphist_dispatch_action "${first_action}"; then
      return
    fi

    # process regular clipboard items
    local output=""
    # Iterate over each line in the array
    for ((i = 0; i < total_lines; i++)); do
      local line="${lines[$i]}"
      local decoded_line
      decoded_line="$(printf '%s\t' "$line" | cliphist decode)"
      if [ $i -lt $((total_lines - 1)) ]; then
        printf -v output '%s%s\n' "$output" "$decoded_line"
      else
        printf -v output '%s%s' "$output" "$decoded_line"
      fi
    done
    echo -n "$output"
  else
    # handle delete mode
    while IFS= read -r line; do
      case "$(cliphist_action_id "${line}")" in
        "${action_wipe}")
          cliphist_dispatch_action "${action_wipe}"
          break
          ;;
        "${action_back}")
          del_mode=false
          cliphist_dispatch_action "${action_back}"
          break
          ;;
        "")
          ;;
        *)
          cliphist delete <<<"${line}"
          dunstify -t 3000 -i "edit-delete" "Deleted" "${line}"
          ;;
      esac
    done
    exit 0
  fi
}

# check if content is binary and handle accordingly
check_content() {
  local line
  read -r line
  if [[ ${line} == *"[[ binary data"* ]]; then
    cliphist decode <<<"$line" | wl-copy
    local img_idx
    img_idx=$(awk -F '\t' '{print $1}' <<<"$line")
    local temp_preview="${XDG_RUNTIME_DIR}/hypr/pastebin-preview_${img_idx}"
    wl-paste >"${temp_preview}"
    dunstify -a "Pastebin:" "Preview: ${img_idx}" -i "${temp_preview}" -t 2000
    return 1
  fi
}

# execute rofi with common parameters
run_rofi() {
  local placeholder="$1"
  shift
  local -a rofi_args=(
    -dmenu
    -theme-str "entry { placeholder: \"${placeholder}\";}"
    -theme-str "${font_override}"
    -theme-str "${r_override}"
    -theme-str "${rofi_position}"
    -theme "${cliphist_style}"
  )

  [[ -n "${cliphist_window_theme:-}" ]] && rofi_args+=(-theme-str "${cliphist_window_theme}")
  [[ -n "${_rofi_opacity:-}" ]] && rofi_args+=(-theme-str "${_rofi_opacity}")
  rofi_args+=(
    -kb-custom-1 "Alt+c"
    -kb-custom-2 "Alt+d"
    -kb-custom-3 "Alt+n"
    -kb-custom-4 "Alt+w"
    -kb-custom-5 "Alt+o"
    -kb-custom-6 "Alt+v"
    -kb-custom-7 "Alt+s"
    -kb-custom-8 "Alt+q"
  )

  local rofi_output=""
  rofi_output="$(rofi "${rofi_args[@]}" "$@")"
  local rofi_status=$?

  if ((rofi_status == 0)); then
    printf '%s' "${rofi_output}"
    return 0
  fi

  if cliphist_action_from_exit_code "${rofi_status}"; then
    return 0
  fi

  return "${rofi_status}"
}

# setup rofi configuration
setup_rofi_config() {
  local cliphist_window_width_em="${ROFI_CLIPHIST_WIDTH_EM:-36}"
  local cliphist_window_height_em="${ROFI_CLIPHIST_HEIGHT_EM:-29}"

  rofi_prepare_standard_context \
    font_scale font_name font_override r_override _rofi_opacity \
    "${ROFI_CLIPHIST_SCALE}" "${ROFI_CLIPHIST_FONT:-$ROFI_FONT}" wallbox same

  [[ "${cliphist_window_width_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || cliphist_window_width_em="36"
  [[ "${cliphist_window_height_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || cliphist_window_height_em="29"

  rofi_picker_compute_window_geometry \
    rofi_position cliphist_window_theme \
    "${font_name}" "${font_scale}" \
    "${cliphist_window_width_em}" "${cliphist_window_height_em}" \
    $((cliphist_window_width_em * font_scale * 2)) $((cliphist_window_height_em * font_scale * 2))
}

# create favorites directory if it doesn't exist
ensure_favorites_dir() {
  local dir
  dir=$(dirname "$favorites_file")
  [ -d "$dir" ] || mkdir -p "$dir"
}

# process favorites file into an array of decoded lines for rofi
prepare_favorites_for_display() {
  if [ ! -f "$favorites_file" ] || [ ! -s "$favorites_file" ]; then
    return 1
  fi

  # read each Base64 encoded favorite as a separate line
  mapfile -t favorites <"$favorites_file"

  # prepare list of representations for rofi
  decoded_lines=()
  for favorite in "${favorites[@]}"; do
    local decoded_favorite
    decoded_favorite=$(echo "$favorite" | base64 --decode)
    # replace newlines with spaces for rofi display
    local single_line_favorite
    single_line_favorite=$(echo "$decoded_favorite" | tr '\n' ' ')
    decoded_lines+=("$single_line_favorite")
  done

  return 0
}

# display clipboard history and copy selected item
show_history() {
  local selected_item
  selected_item=$( (
    printf '%s\t%s\n' "${action_favorites}" "📌 Favorites"
    printf '%s\t%s\n' "${action_options}" "⚙️ Options"
    cliphist list
  ) | run_rofi " 📜 History" -i -display-columns 2 -selected-row 2)

  [ -n "${selected_item}" ] || exit 0

  if printf '%s\n' "${selected_item}" | check_content; then
    process_selections <<<"${selected_item}" | wl-copy
    paste_string "${@}"
    printf '%s\t' "${selected_item}" | cliphist delete
  else
    # binary content - handled by check_content
    paste_string "${@}"
    exit 0
  fi
}

show_image_history() {
  local selected_item=""
  local image_rows=""

  if ! image_rows="$(python3 "${script_dir}/cliphist.image.py")" || [[ -z "${image_rows}" ]]; then
    dunstify -t 3000 -i "dialog-information" "No images in clipboard history."
    return
  fi

  selected_item="$(
    printf '%s\n' "${image_rows}" \
      | run_rofi " 🏞️ Image History..." \
        -display-columns 2 \
        -show-icons \
        -eh 3 \
        -theme-str 'listview { lines: 4; columns: 2; }' \
        -theme-str 'element { enabled: true; orientation: vertical; spacing: 0%; padding: 0%; cursor: pointer; background-color: transparent; text-color: @main-fg; horizontal-align: 0.5; }' \
        -theme-str 'element-text { enabled: false; }' \
        -theme-str 'element-icon { size: 8%; spacing: 0%; padding: 0%; cursor: inherit; background-color: transparent; }' \
        -theme-str 'element selected.normal { background-color: @select-bg; text-color: @select-fg; }'
  )"

  [[ -n "${selected_item}" ]] || exit 0
  if cliphist_dispatch_action "$(cliphist_action_id "${selected_item}")"; then
    return
  fi

  if printf '%s\n' "${selected_item}" | check_content; then
    process_selections <<<"${selected_item}" | wl-copy
    paste_string "${@}"
    printf '%s\t' "${selected_item}" | cliphist delete
  else
    paste_string "${@}"
    exit 0
  fi
}

# delete items from clipboard history
delete_items() {
  export del_mode=true
  local selected_items
  selected_items=$( (
    printf '%s\t%s\n' "${action_back}" "Back"
    cliphist list
  ) | run_rofi " 🗑️ Delete" -i -display-columns 2 -selected-row 1)

  if cliphist_dispatch_action "$(cliphist_action_id "${selected_items}")"; then
    return
  fi
  [ -n "${selected_items}" ] && echo "${selected_items}" | process_selections
}

# favorite clipboard items
view_favorites() {
  prepare_favorites_for_display || {
    dunstify -t 3000 -i "edit-paste" "No favorites."
    return
  }

  local selected_favorite
  selected_favorite=$(printf "Back\n%s\n" "${decoded_lines[@]}" | run_rofi "📌 View Favorites")
  if cliphist_dispatch_action "$(cliphist_action_id "${selected_favorite}")"; then
    return
  fi

  # Handle back navigation
  if [ "$selected_favorite" = "Back" ]; then
    main
    return
  fi

  if [ -n "$selected_favorite" ]; then
    # Find the index of the selected favorite
    local index
    index=$(printf "%s\n" "${decoded_lines[@]}" | grep -nxF "$selected_favorite" | cut -d: -f1)

    # Use the index to get the Base64 encoded favorite
    if [ -n "$index" ]; then
      local selected_encoded_favorite="${favorites[$((index - 1))]}"
      echo "$selected_encoded_favorite" | base64 --decode | wl-copy
      paste_string "${@}"
      dunstify -t 3000 -i "edit-paste" "Copied to clipboard."
    else
      dunstify -t 3000 -i "dialog-error" "Error: Selected favorite not found."
    fi
  fi
}

# add item to favorites
add_to_favorites() {
  ensure_favorites_dir

  local item
  item=$( (
    printf '%s\t%s\n' "${action_back}" "Back"
    cliphist list
  ) | run_rofi "➕ Add to Favorites..." -i -display-columns 2 -selected-row 1)
  if cliphist_dispatch_action "$(cliphist_action_id "${item}")"; then
    return
  fi

  # Handle back navigation
  if [[ "$(cliphist_action_id "${item}")" == "${action_back}" ]]; then
    manage_favorites
    return
  fi

  if [ -n "$item" ]; then
    local full_item
    full_item=$(printf '%s\n' "$item" | cliphist decode)

    local encoded_item
    encoded_item=$(echo "$full_item" | base64 -w 0)

    # Check if the item is already in the favorites file
    if [ -f "$favorites_file" ] && grep -Fxq "$encoded_item" "$favorites_file"; then
      dunstify -t 3000 -i "edit-paste" "Item is already in favorites."
    else
      echo "$encoded_item" >>"$favorites_file"
      dunstify -t 3000 -i "edit-paste" "Added to favorites."
    fi
  fi
}

# delete from favorites
delete_from_favorites() {
  prepare_favorites_for_display || {
    dunstify -t 3000 -i "edit-paste" "No favorites to remove."
    return
  }

  local selected_favorite
  selected_favorite=$(printf "Back\n%s\n" "${decoded_lines[@]}" | run_rofi "➖ Remove from Favorites...")
  if cliphist_dispatch_action "$(cliphist_action_id "${selected_favorite}")"; then
    return
  fi

  # Handle back navigation
  if [ "$selected_favorite" = "Back" ]; then
    manage_favorites
    return
  fi

  if [ -n "$selected_favorite" ]; then
    local index
    index=$(printf "%s\n" "${decoded_lines[@]}" | grep -nxF "$selected_favorite" | cut -d: -f1)

    if [ -n "$index" ]; then
      local selected_encoded_favorite="${favorites[$((index - 1))]}"

      # Handle case where only one item is present
      if [ "$(wc -l <"$favorites_file")" -eq 1 ]; then
        : >"$favorites_file"
      else
        local favorites_tmp
        favorites_tmp="$(mktemp "$(dirname "${favorites_file}")/.cliphist_favorites.XXXXXX")"
        if grep -vF -x "$selected_encoded_favorite" "$favorites_file" >"${favorites_tmp}"; then
          mv "${favorites_tmp}" "$favorites_file" || {
            rm -f "${favorites_tmp}"
            dunstify -t 3000 -i "dialog-error" "Error: Failed to update favorites."
            return
          }
        else
          local grep_status=$?
          if [ "${grep_status}" -eq 1 ]; then
            mv "${favorites_tmp}" "$favorites_file" || {
              rm -f "${favorites_tmp}"
              dunstify -t 3000 -i "dialog-error" "Error: Failed to update favorites."
              return
            }
          else
            rm -f "${favorites_tmp}"
            dunstify -t 3000 -i "dialog-error" "Error: Failed to filter favorites."
            return
          fi
        fi
      fi
      dunstify -t 3000 -i "edit-delete" "Item removed from favorites."
    else
      dunstify -t 3000 -i "dialog-error" "Error: Selected favorite not found."
    fi
  fi
}

# clear all favorites
clear_favorites() {
  if [ -f "$favorites_file" ] && [ -s "$favorites_file" ]; then
    local confirm
    confirm=$(echo -e "Back\nYes\nNo" | run_rofi "☢️ Clear All Favorites?")
    if cliphist_dispatch_action "$(cliphist_action_id "${confirm}")"; then
      return
    fi

    if [ "$confirm" = "Yes" ]; then
      : >"$favorites_file"
      dunstify -t 3000 -i "edit-delete" "All favorites have been deleted."
    elif [ "$confirm" = "Back" ]; then
      manage_favorites
      return
    fi
  else
    dunstify -t 3000 -i "edit-paste" "No favorites to delete."
  fi
}

# manage favorites
manage_favorites() {
  local manage_action
  manage_action=$(echo -e "◀ Back\nAdd to Favorites\nDelete from Favorites\nClear All Favorites" \
    | run_rofi "📓 Manage Favorites")
  if cliphist_dispatch_action "$(cliphist_action_id "${manage_action}")"; then
    return
  fi

  case "${manage_action}" in
    "◀ Back")
      main
      ;;
    "Add to Favorites")
      add_to_favorites
      ;;
    "Delete from Favorites")
      delete_from_favorites
      ;;
    "Clear All Favorites")
      clear_favorites
      ;;
    *)
      [ -n "${manage_action}" ] || return 0
      echo "Invalid action"
      exit 1
      ;;
  esac
}

# clear clipboard history
clear_history() {
  local confirm
  confirm=$(echo -e "Back\nYes\nNo" | run_rofi "☢️ Clear Clipboard History?")
  if cliphist_dispatch_action "$(cliphist_action_id "${confirm}")"; then
    return
  fi

  if [ "$confirm" = "Yes" ]; then
    cliphist wipe
    dunstify -t 3000 -i "edit-clear" "Clipboard history cleared."
  elif [ "$confirm" = "Back" ]; then
    main
    return
  fi
}

ocr_latest_image() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
  local image_line=""
  local image_path=""
  local tesseract_output=""
  local tesseract_package_prefix="tesseract-data-"
  local tesseract_languages_prepared=""
  local tesseract_languages_body="Languages used"
  local pkg=""
  local language=""
  local -a tesseract_default_language=("eng")
  local -a tesseract_languages=("${SCREENSHOT_OCR_TESSERACT_LANGUAGES[@]:-${tesseract_default_language[@]}}")
  local -a tesseract_packages=()

  image_line="$(latest_image_history_entry)" || {
    dunstify -t 3000 -i "dialog-error" "OCR Error" "No images in clipboard history."
    return 1
  }

  tesseract_packages=("${tesseract_languages[@]/#/${tesseract_package_prefix}}")
  tesseract_packages+=("tesseract" "tesseract-data-osd")
  for pkg in "${tesseract_packages[@]}"; do
    if ! pkg_installed "${pkg}"; then
      dunstify -t 5000 -i "dialog-error" "OCR Error" "Required package is not installed: ${pkg}"
      return 1
    fi
  done

  mkdir -p "${runtime_dir}"
  image_path="$(mktemp "${runtime_dir}/cliphist-ocr.XXXXXX.png")" || {
    dunstify -t 3000 -i "dialog-error" "OCR Error" "Failed to create a temporary image path."
    return 1
  }

  if ! cliphist decode <<<"${image_line}" >"${image_path}"; then
    rm -f "${image_path}"
    dunstify -t 3000 -i "dialog-error" "OCR Error" "Failed to decode the latest clipboard image."
    return 1
  fi

  if pkg_installed imagemagick; then
    magick "${image_path}" \
      -colorspace gray \
      -contrast-stretch 0 \
      -level 15%,85% \
      -resize 400% \
      -sharpen 0x1 \
      -auto-threshold triangle \
      -morphology close diamond:1 \
      -deskew 40% \
      "${image_path}"
  fi

  tesseract_languages+=("osd")
  tesseract_languages_prepared=$(
    IFS=+
    printf '%s' "${tesseract_languages[*]}"
  )
  for language in "${tesseract_languages[@]}"; do
    tesseract_languages_body+=$'\n '"${language}"
  done

  tesseract_output="$(
    tesseract \
      --psm 6 \
      --oem 3 \
      -l "${tesseract_languages_prepared}" \
      "${image_path}" \
      stdout \
      2>/dev/null
  )"
  printf '%s' "${tesseract_output}" | wl-copy
  dunstify -t 5000 -i "${image_path}" "OCR" "${#tesseract_output} symbols recognized\n${tesseract_languages_body}"
  rm -f "${image_path}"
}

qr_latest_image() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
  local image_line=""
  local image_path=""
  local qr_output=""

  image_line="$(latest_image_history_entry)" || {
    dunstify -t 3000 -i "dialog-error" "QR Error" "No images in clipboard history."
    return 1
  }

  if ! command -v zbarimg >/dev/null 2>&1; then
    dunstify -t 5000 -i "dialog-error" "QR Error" "zbarimg is not installed."
    return 1
  fi

  mkdir -p "${runtime_dir}"
  image_path="$(mktemp "${runtime_dir}/cliphist-qr.XXXXXX.png")" || {
    dunstify -t 3000 -i "dialog-error" "QR Error" "Failed to create a temporary image path."
    return 1
  }

  if ! cliphist decode <<<"${image_line}" >"${image_path}"; then
    rm -f "${image_path}"
    dunstify -t 3000 -i "dialog-error" "QR Error" "Failed to decode the latest clipboard image."
    return 1
  fi

  qr_output="$(
    zbarimg \
      --quiet \
      --oneshot \
      --raw \
      "${image_path}" \
      2>/dev/null
  )"

  if [[ -z "${qr_output}" ]]; then
    rm -f "${image_path}"
    dunstify -t 3000 -i "dialog-error" "QR Error" "No QR code recognized."
    return 1
  fi

  printf '%s' "${qr_output}" | wl-copy
  dunstify -t 5000 -i "${image_path}" "QR" "Successfully recognized and copied to clipboard."
  rm -f "${image_path}"
}

# show help message
show_help() {
  local exit_code="${1:-0}"
  cat <<EOF
Options:
  -c  | --copy | History            Show clipboard history and copy selected item
  -d  | --delete | Delete           Delete selected item from clipboard history
  -i  | --image-history             Show clipboard image history
  -f  | --favorites| View Favorites              View favorite clipboard items
  -mf | -manage-fav | Manage Favorites  Manage favorite clipboard items
  -sc | --scan-image                OCR the latest clipboard image and copy text
  -qr | --scan-qr                   Decode the latest clipboard QR image and copy text
  -w  | --wipe | Clear History      Clear clipboard history
  -h  | --help | Help               Display this help message

Note: To enable autopaste, install 'wtype' package.
EOF
  exit "${exit_code}"
}

# main function
main() {
  setup_rofi_config

  local main_action
  # show main menu if no arguments are passed
  if [ $# -eq 0 ]; then
    main_action=$(echo -e "History\nImage History\nOCR Latest Image\nQR Latest Image\nDelete\nView Favorites\nManage Favorites\nClear History" \
      | run_rofi "🔎 Choose action")
  else
    main_action="$1"
  fi

  # process user selection
  case "${main_action}" in
    -c | --copy | "History")
      show_history "$@"
      ;;
    -i | --image-history | "Image History")
      show_image_history "$@"
      ;;
    -sc | --scan-image | "OCR Latest Image")
      ocr_latest_image
      ;;
    -qr | --scan-qr | "QR Latest Image")
      qr_latest_image
      ;;
    -d | --delete | "Delete")
      delete_items
      ;;
    -f | --favorites | "View Favorites")
      view_favorites "$@"
      ;;
    -mf | -manage-fav | "Manage Favorites")
      manage_favorites
      ;;
    -w | --wipe | "Clear History")
      clear_history
      ;;
    "")
      exit 0
      ;;
    -h | --help)
      show_help
      ;;
    *)
      printf 'Invalid action: %s\n\n' "${main_action}" >&2
      show_help 1
      ;;
  esac
}

# run main function
main "$@"
