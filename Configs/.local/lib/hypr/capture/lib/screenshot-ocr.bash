ocr_screenshot() {
  local subject="${1:-area}"
  local destination="${2:-clipboard}"
  local ocr_image="${temp_screenshot}"
  local text_file="${save_dir}/${save_text_file}"
  local tesseract_languages_body=""
  local tesseract_output="" ocr_failure="" ocr_warning=""
  local -a tesseract_languages=()

  ocr_capture_subject "${subject}" || {
    screenshot_notify "${NOTIFY_LONG_MS}" "dialog-error" "OCR: screenshot error"
    return 1
  }

  hypr_ocr_prepare_languages tesseract_languages ocr_failure || {
    screenshot_notify "${OCR_ERROR_NOTIFY_MS}" "dialog-error" "OCR: ${ocr_failure%%$'\n'*}" "${ocr_failure#*$'\n'}"
    return 1
  }
  tesseract_languages_body="$(hypr_ocr_language_summary tesseract_languages)"

  hypr_ocr_preprocess_best_effort_into ocr_image ocr_temp_image ocr_warning "${temp_screenshot}" screen
  [[ -z "${ocr_warning}" ]] || screenshot_notify "${NOTIFY_LONG_MS}" "dialog-warning" "OCR: ${ocr_warning}"

  if ! tesseract_output="$(hypr_ocr_recognize "${ocr_image}" "$(hypr_ocr_language_argument tesseract_languages)")"; then
    screenshot_notify "${NOTIFY_LONG_MS}" "dialog-error" "OCR: text recognition failed"
    return 1
  fi

  if [[ -z "${tesseract_output//[[:space:]]/}" ]]; then
    screenshot_notify "${NOTIFY_LONG_MS}" "${temp_screenshot}" "OCR: no text found" "${tesseract_languages_body}"
    return 1
  fi

  deliver_ocr_text "${destination}" "${tesseract_output}" "${text_file}" || return 1
  ocr_notify_success "${destination}" "${text_file}" "${#tesseract_output}" "${tesseract_languages_body}"
}

ocr_capture_subject() {
  local subject="$1"
  local rectangles=""
  local selection=""

  case "${subject}" in
    area | region | selection)
      selection="$(capture_select_geometry frozen "$(capture_visible_workspace_rectangles)")" || return 1
      grim -g "${selection}" "${temp_screenshot}"
      ;;
    smart)
      rectangles="$(capture_active_workspace_rectangles)"
      selection="$(capture_select_geometry frozen "${rectangles}")" || return 1
      selection="$(capture_expand_tiny_selection "${selection}" "${rectangles}")"
      grim -g "${selection}" "${temp_screenshot}"
      ;;
    window | w)
      rectangles="$(capture_active_workspace_rectangles)"
      selection="$(capture_select_geometry frozen "${rectangles}" -r)" || return 1
      grim -g "${selection}" "${temp_screenshot}"
      ;;
    monitor | output | m)
      grim -o "$(focused_output_name)" "${temp_screenshot}"
      ;;
    screen | fullscreen | p)
      grim "${temp_screenshot}"
      ;;
    *)
      screenshot_error_notify "OCR: invalid subject '${subject}'"
      return 1
      ;;
  esac
}

deliver_ocr_text() {
  local destination="$1"
  local text="$2"
  local text_file="$3"

  case "${destination}" in
    "" | clipboard | copy)
      printf '%s' "${text}" | wl-copy --sensitive
      ;;
    save | file)
      printf '%s\n' "${text}" >"${text_file}"
      ;;
    both | copy-save | save-copy)
      printf '%s' "${text}" | wl-copy --sensitive
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

  screenshot_notify "${NOTIFY_LONG_MS}" "${temp_screenshot}" "${summary}" "${body}"
}
