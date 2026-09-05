#!/usr/bin/env bash

# pressing the keybind again dismisses an open menu. Actions re-exec this script
# to switch views, so they must not take that path — it would kill the UI they
# are about to draw and exit.
if [[ -z "${CLIPHIST_REENTRY:-}" ]]; then
  pkill -u "$USER" rofi && exit 0
fi
export CLIPHIST_REENTRY=1

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require system rofi || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/capture/ocr.common.bash" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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
action_delete_entry="__action__:delete-entry"
action_expand="__action__:expand"

cliphist_action_id() {
  printf '%s\n' "${1%%$'\t'*}"
}

cliphist_dispatch_action() {
  local action="${1%%$'\n'*}"
  local payload=""

  [[ "$1" == *$'\n'* ]] && payload="${1#*$'\n'}"

  case "${action}" in
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
      "${0}" --scan-image "${payload}"
      ;;
    "${action_scan_qr}")
      "${0}" --scan-qr "${payload}"
      ;;
    "${action_delete_entry}")
      "${0}" --delete-entry "${payload}"
      ;;
    "${action_expand}")
      "${0}" --expand "${payload}"
      ;;
    *)
      return 1
      ;;
  esac

  return 0
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

# an image entry picked in the menu wins; a text row, a stale id or no selection
# at all falls back to the newest image, which is what the bare flags act on
resolve_image_entry() {
  local id="${1%%$'\t'*}"
  local line=""

  id="${id//[^0-9]/}"
  if [[ -n "${id}" ]]; then
    line="$(cliphist list | grep -m1 -E "^${id}[[:space:]]" || true)"
    if [[ -n "${line}" && "${line}" =~ (\[\[[[:space:]])?binary.*(jpg|jpeg|png|bmp) ]]; then
      printf '%s\n' "${line}"
      return 0
    fi
  fi

  latest_image_history_entry
}

process_selections() {
  local first_action=""

  if [ true != "${del_mode}" ]; then
    mapfile -t lines #! Not POSIX compliant
    total_lines=${#lines[@]}
    first_action="$(cliphist_action_id "${lines[0]:-}")"

    if cliphist_dispatch_action "${first_action}"; then
      return
    fi

    local output=""
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
    -kb-custom-9 "Delete"
    -kb-custom-10 "Alt+e"
    -kb-remove-char-forward "Control+d"
  )

  local rofi_output=""
  rofi_output="$(rofi "${rofi_args[@]}" "$@")"
  local rofi_status=$?

  if ((rofi_status == 0)); then
    printf '%s' "${rofi_output}"
    return 0
  fi

  case "${rofi_status}" in
    10) printf '%s' "${action_copy}" ;;
    11) printf '%s' "${action_delete}" ;;
    12) printf '%s' "${action_favorites}" ;;
    13) printf '%s' "${action_wipe}" ;;
    14) printf '%s' "${action_options}" ;;
    15) printf '%s' "${action_image_history}" ;;
    16) printf '%s\n%s' "${action_scan_image}" "${rofi_output}" ;;
    17) printf '%s\n%s' "${action_scan_qr}" "${rofi_output}" ;;
    18) printf '%s\n%s' "${action_delete_entry}" "${rofi_output}" ;;
    19) printf '%s\n%s' "${action_expand}" "${rofi_output}" ;;
    *) return "${rofi_status}" ;;
  esac

  return 0
}

setup_rofi_config() {
  local cliphist_window_width_em="${ROFI_CLIPHIST_WIDTH_EM:-36}"
  local cliphist_window_height_em="${ROFI_CLIPHIST_HEIGHT_EM:-29}"
  local font_scale=""
  local font_name=""

  rofi_prepare_standard_context \
    font_scale font_name font_override r_override _rofi_opacity \
    "${ROFI_CLIPHIST_SCALE:-}" "${ROFI_CLIPHIST_FONT:-${ROFI_FONT:-}}" wallbox same

  [[ "${cliphist_window_width_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || cliphist_window_width_em="36"
  [[ "${cliphist_window_height_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || cliphist_window_height_em="29"

  rofi_picker_compute_window_geometry \
    rofi_position cliphist_window_theme \
    "${font_name}" "${font_scale}" \
    "${cliphist_window_width_em}" "${cliphist_window_height_em}" \
    $((cliphist_window_width_em * font_scale * 2)) $((cliphist_window_height_em * font_scale * 2))
}

prepare_favorites_for_display() {
  if [ ! -f "$favorites_file" ] || [ ! -s "$favorites_file" ]; then
    return 1
  fi

  mapfile -t favorites <"$favorites_file"

  decoded_lines=()
  for favorite in "${favorites[@]}"; do
    local decoded_favorite
    decoded_favorite=$(echo "$favorite" | base64 --decode)
    local single_line_favorite
    single_line_favorite=$(echo "$decoded_favorite" | tr '\n' ' ')
    local masked_favorite
    masked_favorite=$(printf '%s' "$single_line_favorite" | mask_secret_field 1)
    if [ "$masked_favorite" != "$single_line_favorite" ]; then
      single_line_favorite="${masked_favorite} #$((${#decoded_lines[@]} + 1))"
    fi
    decoded_lines+=("$single_line_favorite")
  done

  return 0
}

# Token-shaped values are shown masked in the picker. rofi returns the whole
# line, but cliphist decode/delete key off the leading id, so rewriting the
# preview column is display-only.
mask_secret_field() {
  awk -F '\t' -v f="${1:-2}" 'BEGIN { OFS = "\t" }
    {
      label = ""
      if ($f ~ /ghp_[A-Za-z0-9]{20,}/ || $f ~ /gh[ousr]_[A-Za-z0-9]{20,}/) label = "GitHub token"
      else if ($f ~ /github_pat_[A-Za-z0-9_]{20,}/) label = "GitHub fine-grained token"
      else if ($f ~ /glpat-[A-Za-z0-9_-]{15,}/) label = "GitLab token"
      else if ($f ~ /xox[abprs]-[A-Za-z0-9-]{10,}/) label = "Slack token"
      else if ($f ~ /sk-(ant-)?[A-Za-z0-9_-]{20,}/) label = "API key"
      else if ($f ~ /AKIA[0-9A-Z]{16}/) label = "AWS access key"
      else if ($f ~ /AIza[0-9A-Za-z_-]{35}/) label = "Google API key"
      else if ($f ~ /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\./) label = "JWT"
      else if ($f ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) label = "Private key"
      if (label != "") $f = "\342\200\242\342\200\242\342\200\242\342\200\242\342\200\242\342\200\242\342\200\242\342\200\242  " label
      print
    }'
}

mask_secret_previews() { mask_secret_field 2; }

# Same detection, applied to fully decoded content. The list only ever sees a
# truncated preview, so a token past preview-width is not masked there — this
# is what keeps expand from being a way around the mask.
secret_label() {
  local flat="${1//$'\n'/ }"
  local masked=""

  masked="$(printf 'x\t%s\n' "${flat}" | mask_secret_field 2 | cut -f2-)"
  [[ "${masked}" != "${flat}" ]] && printf '%s' "${masked##*  }"
  return 0
}

show_history() {
  local selected_item
  selected_item=$( (
    printf '%s\t%s\n' "${action_favorites}" "📌 Favorites"
    printf '%s\t%s\n' "${action_options}" "⚙️ Options"
    cliphist list | mask_secret_previews
  ) | run_rofi " 📜 History" -i -display-columns 2 -selected-row 2)

  [ -n "${selected_item}" ] || exit 0

  if printf '%s\n' "${selected_item}" | check_content; then
    process_selections <<<"${selected_item}" | wl-copy
    paste_string "${@}"
    printf '%s\t' "${selected_item}" | cliphist delete
  else
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
        -theme-str 'element { enabled: true; orientation: vertical; spacing: 0%; padding: 0%; cursor: pointer; background-color: transparent; text-color: @foreground; horizontal-align: 0.5; }' \
        -theme-str 'element-text { enabled: false; }' \
        -theme-str 'element-icon { size: 8%; spacing: 0%; padding: 0%; cursor: inherit; background-color: transparent; }' \
        -theme-str 'element selected.normal { background-color: @selected-background; text-color: @selected-foreground; }'
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

delete_items() {
  export del_mode=true
  local selected_items
  selected_items=$( (
    printf '%s\t%s\n' "${action_back}" "Back"
    cliphist list | mask_secret_previews
  ) | run_rofi " 🗑️ Delete" -i -display-columns 2 -selected-row 1)

  if cliphist_dispatch_action "$(cliphist_action_id "${selected_items}")"; then
    return
  fi
  [ -n "${selected_items}" ] && echo "${selected_items}" | process_selections
}

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

  if [ "$selected_favorite" = "Back" ]; then
    main
    return
  fi

  if [ -n "$selected_favorite" ]; then
    local index
    index=$(printf "%s\n" "${decoded_lines[@]}" | grep -nxF "$selected_favorite" | cut -d: -f1)

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

add_to_favorites() {
  mkdir -p "$(dirname "$favorites_file")"

  local item
  item=$( (
    printf '%s\t%s\n' "${action_back}" "Back"
    cliphist list | mask_secret_previews
  ) | run_rofi "➕ Add to Favorites..." -i -display-columns 2 -selected-row 1)
  if cliphist_dispatch_action "$(cliphist_action_id "${item}")"; then
    return
  fi

  if [[ "$(cliphist_action_id "${item}")" == "${action_back}" ]]; then
    manage_favorites
    return
  fi

  if [ -n "$item" ]; then
    local full_item
    full_item=$(printf '%s\n' "$item" | cliphist decode)

    local encoded_item
    encoded_item=$(echo "$full_item" | base64 -w 0)

    if [ -f "$favorites_file" ] && grep -Fxq "$encoded_item" "$favorites_file"; then
      dunstify -t 3000 -i "edit-paste" "Item is already in favorites."
    else
      echo "$encoded_item" >>"$favorites_file"
      dunstify -t 3000 -i "edit-paste" "Added to favorites."
    fi
  fi
}

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

  if [ "$selected_favorite" = "Back" ]; then
    manage_favorites
    return
  fi

  if [ -n "$selected_favorite" ]; then
    local index
    index=$(printf "%s\n" "${decoded_lines[@]}" | grep -nxF "$selected_favorite" | cut -d: -f1)

    if [ -n "$index" ]; then
      local selected_encoded_favorite="${favorites[$((index - 1))]}"

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

ocr_image_entry() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
  local image_line=""
  local image_path=""
  local ocr_image=""
  local tesseract_output=""
  local tesseract_languages_body=""
  local -a tesseract_languages=()

  image_line="$(resolve_image_entry "${1:-}")" || {
    dunstify -t 3000 -i "dialog-error" "OCR Error" "No images in clipboard history."
    return 1
  }

  hypr_ocr_prepare_languages tesseract_languages || {
    dunstify -t 7000 -i "dialog-error" "OCR Error" "${HYPR_OCR_ERROR}"
    return 1
  }
  # Clipboard images arrive at an arbitrary rotation, so this path also asks for
  # orientation and script detection; a fresh screen grab never needs it.
  tesseract_languages+=("osd")
  tesseract_languages_body="$(hypr_ocr_language_summary tesseract_languages)"

  mkdir -p "${runtime_dir}"
  image_path="$(mktemp "${runtime_dir}/cliphist-ocr.XXXXXX.png")" || {
    dunstify -t 3000 -i "dialog-error" "OCR Error" "Failed to create a temporary image path."
    return 1
  }

  if ! cliphist decode <<<"${image_line}" >"${image_path}"; then
    rm -f "${image_path}"
    dunstify -t 3000 -i "dialog-error" "OCR Error" "Failed to decode the clipboard image."
    return 1
  fi

  hypr_ocr_preprocess ocr_image "${image_path}" image

  if ! tesseract_output="$(hypr_ocr_recognize "${ocr_image}" "$(hypr_ocr_language_argument tesseract_languages)")"; then
    rm -f "${image_path}" "${HYPR_OCR_TEMP_IMAGE}"
    dunstify -t 5000 -i "dialog-error" "OCR Error" "Text recognition failed."
    return 1
  fi

  printf '%s' "${tesseract_output}" | wl-copy
  dunstify -t 5000 -i "${image_path}" "OCR" "${#tesseract_output} symbols recognized\n${tesseract_languages_body}"
  rm -f "${image_path}" "${HYPR_OCR_TEMP_IMAGE}"
}

# Delete on a highlighted row drops just that entry and reopens the list, so
# several can go in a row without walking back through the menu
delete_entry() {
  local line="${1:-}"
  local id="${line%%$'\t'*}"

  id="${id//[^0-9]/}"
  if [[ -n "${id}" ]]; then
    line="$(cliphist list | grep -m1 -E "^${id}[[:space:]]" || true)"
    if [[ -n "${line}" ]]; then
      cliphist delete <<<"${line}"
      dunstify -t 2000 -i "edit-delete" "Deleted" "$(printf '%s' "${line}" | cut -c1-60)"
    fi
  fi

  show_history
}

# the list truncates at preview-width; this shows the entry in full, folded so
# long lines stay readable, and Enter copies the whole thing
expand_entry() {
  local line="${1:-}"
  local id="${line%%$'\t'*}"
  local text=""
  local choice=""
  local label=""

  id="${id//[^0-9]/}"
  [[ -n "${id}" ]] && text="$(printf '%s\t' "${id}" | cliphist decode)"
  if [[ -z "${text}" ]]; then
    show_history
    return
  fi

  label="$(secret_label "${text}")"
  if [[ -n "${label}" ]]; then
    dunstify -t 3000 -i "dialog-password" "Expand blocked" "Entry looks like a ${label}."
    show_history
    return
  fi

  choice="$(printf '%s\n' "${text}" \
    | fold -s -w "${ROFI_CLIPHIST_EXPAND_WIDTH:-100}" \
    | rofi -dmenu -i -p " 🔍 Entry" \
        -theme "${cliphist_style}" \
        -theme-str "${font_override}" \
        -theme-str "${r_override}" \
        -theme-str "${rofi_position}" || true)"
  [[ -n "${choice}" ]] && printf '%s' "${text}" | wl-copy

  show_history
}

qr_image_entry() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
  local image_line=""
  local image_path=""
  local qr_output=""

  image_line="$(resolve_image_entry "${1:-}")" || {
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
    dunstify -t 3000 -i "dialog-error" "QR Error" "Failed to decode the clipboard image."
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

  # QR codes routinely carry secrets such as otpauth:// URIs, so the decoded
  # value is copied as sensitive and never lands in clipboard history
  printf '%s' "${qr_output}" | wl-copy --sensitive
  dunstify -t 5000 -i "${image_path}" "QR" "Successfully recognized and copied to clipboard."
  rm -f "${image_path}"
}

# Non-interactive API for the quickshell panel: the favourites store lives here,
# so the panel asks this script rather than reimplementing base64 line handling.
panel_json() {
  local favorites_json="[]"
  if [ -f "$favorites_file" ] && [ -s "$favorites_file" ]; then
    favorites_json="$(
      while IFS= read -r encoded; do
        [ -n "$encoded" ] || continue
        printf '%s' "$encoded" | base64 --decode 2>/dev/null | tr '\n' ' '
        printf '\n'
      done <"$favorites_file" | jq -R -s 'split("\n") | map(select(length > 0)) |
        to_entries | map({index: (.key + 1), text: .value})'
    )"
  fi

  cliphist list | jq -R -s --argjson favorites "$favorites_json" '
    split("\n") | map(select(length > 0)) | map(split("\t") | {
      id: .[0],
      preview: (.[1:] | join("\t"))
    }) | map(. + {image: (.preview | test("\\[\\[ binary data"))})
    | {entries: ., favorites: $favorites}'
}

panel_copy_id() {
  local id="$1"
  [ -n "$id" ] || return 1
  printf '%s\t' "$id" | cliphist decode | wl-copy
  # the watcher re-stores it at the top, so drop the stale row
  printf '%s\t' "$id" | cliphist delete
  # the panel closes as this runs; give the compositor a moment to hand focus
  # back before typing into whatever was underneath
  sleep "${CLIPHIST_PASTE_DELAY:-0.2}"
  paste_string
}

panel_delete_id() {
  local id="$1"
  [ -n "$id" ] || return 1
  printf '%s\t' "$id" | cliphist delete
}

panel_fav_add_id() {
  local id="$1"
  [ -n "$id" ] || return 1
  local encoded
  encoded="$(printf '%s\t' "$id" | cliphist decode | base64 -w 0)"
  mkdir -p "$(dirname "$favorites_file")"
  if [ -f "$favorites_file" ] && grep -Fxq "$encoded" "$favorites_file"; then
    return 0
  fi
  printf '%s\n' "$encoded" >>"$favorites_file"
}

panel_fav_remove_index() {
  local index="$1"
  [ -n "$index" ] && [ -f "$favorites_file" ] || return 1
  sed -i "${index}d" "$favorites_file"
}

panel_fav_copy_index() {
  local index="$1"
  [ -n "$index" ] && [ -f "$favorites_file" ] || return 1
  sed -n "${index}p" "$favorites_file" | base64 --decode | wl-copy
}

show_help() {
  local exit_code="${1:-0}"
  cat <<EOF
Options:
  -c  | --copy | History            Show clipboard history and copy selected item
  -d  | --delete | Delete           Delete selected item from clipboard history
  -i  | --image-history             Show clipboard image history
  -f  | --favorites| View Favorites              View favorite clipboard items
  -mf | -manage-fav | Manage Favorites  Manage favorite clipboard items
  -sc | --scan-image [entry]        OCR an image entry (default: latest) and copy text
  -qr | --scan-qr [entry]           Decode a QR image entry (default: latest) and copy text
  -de | --delete-entry [entry]      Delete one entry (Delete key in the list)
  -x  | --expand [entry]            Show an entry in full (Alt+e in the list)
  -w  | --wipe | Clear History      Clear clipboard history
  -h  | --help | Help               Display this help message

Panel API (non-interactive, used by the quickshell popup):
  --panel-json                      Emit history entries and favourites as JSON
  --panel-copy <id>                 Copy a history entry to the clipboard
  --panel-delete <id>               Delete a history entry
  --panel-fav-add <id>              Add a history entry to favourites
  --panel-fav-remove <index>        Remove favourite by 1-based index
  --panel-fav-copy <index>          Copy favourite by 1-based index

Note: To enable autopaste, install 'wtype' package.
EOF
  exit "${exit_code}"
}

main() {
  setup_rofi_config

  local main_action
  if [ $# -eq 0 ]; then
    main_action=$(echo -e "History\nImage History\nOCR Latest Image\nQR Latest Image\nDelete\nView Favorites\nManage Favorites\nClear History" \
      | run_rofi "🔎 Choose action")
  else
    main_action="$1"
  fi

  case "${main_action}" in
    -c | --copy | "History")
      show_history "$@"
      ;;
    -i | --image-history | "Image History")
      show_image_history "$@"
      ;;
    -sc | --scan-image | "OCR Latest Image")
      ocr_image_entry "${2:-}"
      ;;
    -qr | --scan-qr | "QR Latest Image")
      qr_image_entry "${2:-}"
      ;;
    -de | --delete-entry)
      delete_entry "${2:-}"
      ;;
    -x | --expand)
      expand_entry "${2:-}"
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
    --panel-json)
      panel_json
      ;;
    --panel-copy)
      panel_copy_id "$2"
      ;;
    --panel-delete)
      panel_delete_id "$2"
      ;;
    --panel-fav-add)
      panel_fav_add_id "$2"
      ;;
    --panel-fav-remove)
      panel_fav_remove_index "$2"
      ;;
    --panel-fav-copy)
      panel_fav_copy_index "$2"
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

main "$@"
