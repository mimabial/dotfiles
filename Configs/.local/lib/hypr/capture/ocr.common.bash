#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Callers own notifications; recoverable details use HYPR_OCR_ERROR.

HYPR_OCR_ERROR=""
HYPR_OCR_TEMP_IMAGE=""

hypr_ocr_languages_into() {
  local -n languages_ref="$1"
  local raw="" language=""
  local -a unique=()
  local -A seen=()

  if [[ "$(declare -p SCREENSHOT_OCR_TESSERACT_LANGUAGES 2>/dev/null)" == "declare -a"* ]]; then
    languages_ref=("${SCREENSHOT_OCR_TESSERACT_LANGUAGES[@]}")
  else
    raw="${SCREENSHOT_OCR_LANGS:-eng}"
    raw="${raw//[+,]/ }"
    read -r -a languages_ref <<<"${raw}"
  fi

  for language in "${languages_ref[@]:-}"; do
    [[ -n "${language}" && -z "${seen[${language}]:-}" ]] || continue
    seen["${language}"]=1
    unique+=("${language}")
  done
  languages_ref=("${unique[@]:-eng}")
}

hypr_ocr_prepare_languages() {
  local -n prepared_ref="$1"
  local installed="" language="" missing=""

  HYPR_OCR_ERROR=""
  if ! command -v tesseract >/dev/null 2>&1; then
    HYPR_OCR_ERROR="tesseract is not installed"
    return 1
  fi

  hypr_ocr_languages_into prepared_ref
  if ! installed="$(tesseract --list-langs 2>/dev/null)"; then
    HYPR_OCR_ERROR="failed to list tesseract languages"
    return 1
  fi
  installed="${installed#*$'\n'}"

  for language in "${prepared_ref[@]}"; do
    [[ $'\n'"${installed}"$'\n' == *$'\n'"${language}"$'\n'* ]] || missing+="${missing:+, }${language}"
  done

  if [[ -n "${missing}" ]]; then
    HYPR_OCR_ERROR="missing tesseract language data"$'\n'"Missing: ${missing}"$'\n'"Installed: ${installed//$'\n'/, }"
    return 1
  fi
}

hypr_ocr_language_argument() {
  local -n languages_ref="$1"
  local IFS=+
  printf '%s' "${languages_ref[*]}"
}

hypr_ocr_language_summary() {
  local -n languages_ref="$1"
  local language body="Languages used"

  for language in "${languages_ref[@]}"; do
    body+=$'\n '"${language}"
  done
  printf '%s' "${body}"
}

# Returns the image path by name so temporary-file state stays in the caller.
# Screen captures use lighter preprocessing than arbitrary clipboard images.
hypr_ocr_preprocess() {
  local -n image_ref="$1"
  local input="$2"
  local profile="${3:-screen}"
  local -a pipeline=()

  HYPR_OCR_ERROR=""
  HYPR_OCR_TEMP_IMAGE=""
  image_ref="${input}"

  [[ "${SCREENSHOT_OCR_PREPROCESS:-1}" == "1" ]] || return 0

  if ! command -v magick >/dev/null 2>&1; then
    HYPR_OCR_ERROR="imagemagick is not installed, recognition accuracy is reduced"
    return 0
  fi

  case "${profile}" in
    image)
      pipeline=(-colorspace gray -contrast-stretch 0 -level "15%,85%" -resize 400%
        -sharpen 0x1 -auto-threshold triangle -morphology close diamond:1 -deskew 40%)
      ;;
    *)
      pipeline=(-colorspace gray -contrast-stretch 0 -resize 300% -sharpen 0x1 -deskew 40%)
      ;;
  esac

  if ! HYPR_OCR_TEMP_IMAGE="$(mktemp -t hypr_ocr_XXXXXX.png)"; then
    HYPR_OCR_ERROR="failed to create a preprocessing image"
    return 0
  fi
  if magick "${input}" "${pipeline[@]}" "${HYPR_OCR_TEMP_IMAGE}" 2>/dev/null; then
    image_ref="${HYPR_OCR_TEMP_IMAGE}"
    return 0
  fi

  rm -f "${HYPR_OCR_TEMP_IMAGE}"
  HYPR_OCR_TEMP_IMAGE=""
  HYPR_OCR_ERROR="image preprocessing failed, using the original image"
}

hypr_ocr_recognize() {
  local image="$1"
  local languages="$2"

  tesseract \
    "${image}" \
    stdout \
    --oem "${SCREENSHOT_OCR_OEM:-1}" \
    --psm "${SCREENSHOT_OCR_PSM:-6}" \
    --dpi "${SCREENSHOT_OCR_DPI:-300}" \
    -l "${languages}" \
    -c preserve_interword_spaces=1 \
    2>/dev/null
}
