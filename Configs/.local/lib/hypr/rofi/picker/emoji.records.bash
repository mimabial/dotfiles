#!/usr/bin/env bash

emoji_clean_recent_records() {
  local target_file="$1"
  [[ ! -f "${target_file}" ]] && return
  local tmp
  tmp=$(mktemp)
  awk -F'\t' 'BEGIN{OFS="\t"}{
    e=$1; d=$2;
    gsub(/🏻|🏼|🏽|🏾|🏿/,"",e);
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",e);
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",d);
    if (e == "") next;
    if (index(d, e " ") == 1) d=substr(d, length(e) + 2);
    if (!seen[e]++) print e,d;
  }' "${target_file}" >"${tmp}" && mv "${tmp}" "${target_file}"
}

emoji_save_recent_record() {
  local emoji_line="$1"
  local emoji_field=""
  emoji_line="$(emoji_strip_skin_tones "${emoji_line}")"
  emoji_field="${emoji_line%%$'\t'*}"
  emoji_field="${emoji_field//[$' \t\r\n']/}"
  [[ -n "${emoji_field}" ]] || return 0
  rofi_picker_save_recent_entry "${recent_data}" "emoji_recent" "${emoji_line}" "${ROFI_PICKER_RECENT_LIMIT}"
}

emoji_write_selection_source() {
  local target_file="$1"

  {
    if [[ -f "${favorites_data}" ]] && [[ -s "${favorites_data}" ]]; then
      local fav_count
      fav_count=$(wc -l <"${favorites_data}" 2>/dev/null || echo 0)
      if [ "$fav_count" -gt 0 ]; then
        rofi_picker_category_entry "⭐ Favorites (${fav_count} emojis)" favorites
      fi
    fi

    rofi_picker_recent_category_entry "${recent_data}" "🕒" "Recently Used" "emojis" || true

    cat "${emoji_data}"
  } >"${target_file}"
}

emoji_write_display_rows() {
  local source_file="$1"
  local target_file="$2"

  awk -F'\t' -v category_tag="${PICKER_CATEGORY_TAG}" '{
    e=$1; l=$2;
    if (l != "" && index(l, category_tag) != 1) {
      print e " " l;
    } else {
      print e;
    }
  }' "${source_file}" >"${target_file}"
}

emoji_prepare_selection_workspace_into() {
  local -n workspace_ref="$1"
  workspace_ref[directory]="$(mktemp -d "${TMPDIR:-/tmp}/emoji_select.XXXXXX")" || return 1
  workspace_ref[records_file]="${workspace_ref[directory]}/raw"
  workspace_ref[display_file]="${workspace_ref[directory]}/display"
  emoji_write_selection_source "${workspace_ref[records_file]}" || return 1
  emoji_write_display_rows "${workspace_ref[records_file]}" "${workspace_ref[display_file]}" || return 1
}

emoji_category_source_file() {
  local category="$1"
  local category_file="${emoji_categories_dir}/${category}.db"

  case "${category}" in
    recent)
      if [[ ! -f "${recent_data}" ]] || [[ ! -s "${recent_data}" ]]; then
        dunstify -t "${NOTIFY_MS}" -i "face-smile" "No recently used emojis"
        return 1
      fi
      ;;
    favorites)
      if [[ ! -f "${favorites_data}" ]] || [[ ! -s "${favorites_data}" ]]; then
        dunstify -t "${NOTIFY_MS}" -i "face-smile" "No favorite emojis yet"
        return 1
      fi
      category_file="${favorites_data}"
      ;;
    *)
      if [[ ! -f "${category_file}" ]]; then
        dunstify -t "${NOTIFY_MS}" -i "dialog-error" "Category file not found: ${category}"
        return 1
      fi
      ;;
  esac

  [[ "${category}" == "recent" ]] && category_file="${recent_data}"
  printf '%s\n' "${category_file}"
}

emoji_prepare_category_workspace_into() {
  local -n workspace_ref="$1"
  local category_file="$2"
  workspace_ref[directory]="$(mktemp -d "${TMPDIR:-/tmp}/emoji_category.XXXXXX")" || return 1
  workspace_ref[menu_file]="${workspace_ref[directory]}/menu"
  {
    printf '%s\n' "${PICKER_BACK_ENTRY}"
    cat "${category_file}"
  } >"${workspace_ref[menu_file]}"
}

emoji_prepare_recent_files() {
  rofi_picker_prepare_data_file "${recent_data}" emoji_clean_recent_records
  rofi_picker_prepare_data_file "${favorites_data}" emoji_clean_recent_records
}

emoji_normalize_selection_record() {
  if [[ "$1" == *$'\t'* ]]; then
    printf '%s\n' "$1"
    return 0
  fi

  local emoji_token desc_token
  emoji_token="${1%% *}"
  desc_token="${1#"${emoji_token}"}"
  desc_token="${desc_token# }"
  printf '%s\t%s\n' "${emoji_token}" "${desc_token}"
}
