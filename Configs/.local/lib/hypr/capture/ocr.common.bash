#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# The OCR engine shared by capture/screenshot.sh and rofi/cliphist.sh. Nothing
# here notifies: the two callers have different notification surfaces, so they
# read HYPR_OCR_ERROR and report it themselves.

HYPR_OCR_ERROR=""
HYPR_OCR_TEMP_IMAGE=""

# The configured languages, into the named array. SCREENSHOT_OCR_LANGS is the
# documented knob and accepts "eng+fra" or "eng,fra";
# SCREENSHOT_OCR_TESSERACT_LANGUAGES overrides it with a pre-split array.
hypr_ocr_languages_into() {
  local -n languages_ref="$1"
  local raw=""

  if [[ "$(declare -p SCREENSHOT_OCR_TESSERACT_LANGUAGES 2>/dev/null)" == "declare -a"* ]]; then
    languages_ref=("${SCREENSHOT_OCR_TESSERACT_LANGUAGES[@]}")
  else
    raw="${SCREENSHOT_OCR_LANGS:-${OMARCHY_OCR_LANGS:-eng}}"
    raw="${raw//[+,]/ }"
    # shellcheck disable=SC2206
    languages_ref=(${raw})
  fi

  mapfile -t languages_ref < <(printf '%s\n' "${languages_ref[@]:-}" | awk 'NF && !seen[$0]++')
  ((${#languages_ref[@]} > 0)) || languages_ref=("eng")
}

# Resolve and validate in one step. Asking tesseract what it can load beats
# probing for distro packages: it is the thing that has to succeed, and it holds
# for language data installed by any means.
hypr_ocr_prepare_languages() {
  local -n prepared_ref="$1"
  local installed="" language="" missing=""

  HYPR_OCR_ERROR=""
  if ! command -v tesseract >/dev/null 2>&1; then
    HYPR_OCR_ERROR="tesseract is not installed"
    return 1
  fi

  hypr_ocr_languages_into prepared_ref
  installed="$(tesseract --list-langs 2>/dev/null | tail -n +2)"

  for language in "${prepared_ref[@]}"; do
    grep -Fxq "${language}" <<<"${installed}" || missing+="${missing:+, }${language}"
  done

  if [[ -n "${missing}" ]]; then
    HYPR_OCR_ERROR="missing tesseract language data"$'\n'"Missing: ${missing}"$'\n'"Installed: ${installed//$'\n'/, }"
    return 1
  fi
}

# "eng+fra" for tesseract -l, from the array named by $1.
hypr_ocr_language_argument() {
  local -n languages_ref="$1"
  local IFS=+
  printf '%s' "${languages_ref[*]}"
}

# The multi-line "Languages used" body both callers show in their notification.
hypr_ocr_language_summary() {
  local -n languages_ref="$1"
  local language body="Languages used"

  for language in "${languages_ref[@]}"; do
    body+=$'\n '"${language}"
  done
  printf '%s' "${body}"
}

# Sets the named variable to the path to hand tesseract: a preprocessed copy
# when that succeeds, otherwise the input untouched. Any copy it makes is also
# recorded in HYPR_OCR_TEMP_IMAGE for the caller to clean up -- which is why the
# result comes back by name and not on stdout, since a command substitution
# would strand that path in the subshell.
#
# The profile picks the pipeline, and the two are not interchangeable:
#   screen  crisp screen captures at a known scale -- a light touch, because
#           binarising anti-aliased UI text loses strokes.
#   image   arbitrary clipboard images of unknown provenance and scale -- more
#           upscaling and a hard threshold, which is what makes low-quality or
#           photographed text legible.
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

  HYPR_OCR_TEMP_IMAGE="$(mktemp -t hypr_ocr_XXXXXX.png)"
  if magick "${input}" "${pipeline[@]}" "${HYPR_OCR_TEMP_IMAGE}" 2>/dev/null; then
    image_ref="${HYPR_OCR_TEMP_IMAGE}"
    return 0
  fi

  rm -f "${HYPR_OCR_TEMP_IMAGE}"
  HYPR_OCR_TEMP_IMAGE=""
  HYPR_OCR_ERROR="image preprocessing failed, using the original image"
}

# Recognized text on stdout. The tuning knobs apply to both callers.
hypr_ocr_recognize() {
  local image="$1"
  local languages="$2"

  HYPR_OCR_ERROR=""
  if ! tesseract \
    "${image}" \
    stdout \
    --oem "${SCREENSHOT_OCR_OEM:-1}" \
    --psm "${SCREENSHOT_OCR_PSM:-6}" \
    --dpi "${SCREENSHOT_OCR_DPI:-300}" \
    -l "${languages}" \
    -c preserve_interword_spaces=1 \
    2>/dev/null; then
    HYPR_OCR_ERROR="text recognition failed"
    return 1
  fi
}
