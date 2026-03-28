#!/usr/bin/env bash

pkill -u "$USER" rofi && exit 0

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

emoji_dir=${HYPR_CONFIG_HOME:-$HOME/.config/hypr}
emoji_data="${emoji_dir}/emoji.db"
emoji_categories_dir="${emoji_dir}/emoji-categories"
cache_dir="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}"
recent_data="${cache_dir}/landing/show_emoji.recent"
favorites_data="${cache_dir}/landing/emoji_favorites"
EMOJI_ICONLESS_THEME_STR='listview { show-icons: false; } element { children: [ "element-text" ]; } element-icon { enabled: false; size: 0em; width: 0em; padding: 0; margin: 0; border: 0; }'
EMOJI_MULTI_PERSON="🤝👫👬👭🧑‍🤝‍🧑💑👩‍❤️‍👨👨‍❤️‍👨👩‍❤️‍👩🧑‍❤️‍🧑💏👩‍❤️‍💋‍👨👨‍❤️‍💋‍👨👩‍❤️‍💋‍👩🧑‍❤️‍💋‍🧑"
EMOJI_GENDER_VARIANTS="🧑👱🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵️💂🥷👷🤴👸👳👲🧕🤵👰🦸🦹🧙🧚🧛🧜🧝🧞💆💇🚶🧍🧎🏃🕺💃🧖🧗🤸🏌️🏄🚣🏊⛹️🏋️🚴🚵🤽🤾🤹🧘🧑‍🎓🧑‍🏫🧑‍⚕️🧑‍🌾🧑‍🍳🧑‍🔧🧑‍🏭🧑‍💼🧑‍🔬🧑‍💻🧑‍🎤🧑‍🎨🧑‍✈️🧑‍🚀🧑‍🚒🧑‍🦯🧑‍🦼🧑‍🦽"
EMOJI_SKIN_TONE_SUPPORTED="👋🤚🖐️✋🖖🫱🫲🫳🫴🫷🫸👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆🫵👇☝️👍👎✊👊🤛🤜👏🙌🫶👐🤲🙏✍️💅🤳💪🦵🦶👂🦻👃🫦🧒👦👧🧑👱👨👩🧔👴👵🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵️💂🥷👷🫅🤴👸👳👲🧕🤵👰🤰🫄🫃🤱👼🎅🤶🧑‍🎄🦸🦹🧙🧚🧛🧜🧝🧞🧟💆💇🚶🧍🧎🏃💃🕺🕴️👯🧖🧗🤺🏇⛷️🏂🏌️🏄🚣🏊⛹️🏋️🚴🚵🤸🤼🤽🤾🤹🛀🛌🧘"
EMOJI_SKIN_TONE_MENU=$'Default\n🏿 Dark\n🏾 Medium-Dark\n🏽 Medium\n🏼 Medium-Light\n🏻 Light'

clean_emoji_file() {
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

emoji_strip_skin_tones() {
  local emoji_text="$1"
  emoji_text="${emoji_text//🏻/}"
  emoji_text="${emoji_text//🏼/}"
  emoji_text="${emoji_text//🏽/}"
  emoji_text="${emoji_text//🏾/}"
  emoji_text="${emoji_text//🏿/}"
  printf '%s' "${emoji_text}"
}

save_recent_entry() {
  local emoji_line="$1"
  local emoji_field=""
  emoji_line="$(emoji_strip_skin_tones "${emoji_line}")"
  emoji_field="${emoji_line%%$'\t'*}"
  emoji_field="${emoji_field//[$' \t\r\n']/}"
  [[ -n "${emoji_field}" ]] || return 0
  rofi_picker_save_recent_entry "${recent_data}" "emoji_recent" "${emoji_line}" 50
}

setup_rofi_config() {
  local font_scale
  local font_name
  rofi_prepare_standard_context \
    font_scale font_name font_override r_override _rofi_opacity \
    "${ROFI_EMOJI_SCALE}" "${ROFI_EMOJI_FONT:-$ROFI_FONT}" wallbox same

  local emoji_window_width_em="${ROFI_EMOJI_WIDTH_EM:-36}"
  local emoji_window_height_em="${ROFI_EMOJI_HEIGHT_EM:-30}"
  [[ "${emoji_window_width_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || emoji_window_width_em="40.5"
  [[ "${emoji_window_height_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || emoji_window_height_em="30"

  rofi_picker_compute_window_position \
    rofi_position "${font_name}" "${font_scale}" \
    "${emoji_window_width_em}" "${emoji_window_height_em}" \
    $((81 * font_scale)) $((60 * font_scale))
}

emoji_menu_base_opts() {
  local theme_name="$1"
  local -n opts_ref="$2"

  opts_ref=(-no-config -no-default-config -theme "${theme_name}")
  [[ -n "${_rofi_opacity}" ]] && opts_ref+=("-theme-str" "${_rofi_opacity}")
}

emoji_style_menu_args() {
  local style_type="$1"
  local -n args_ref="$2"

  args_ref=()
  case "${style_type}" in
    2 | grid)
      args_ref+=(-theme-str "listview {columns: 2;}")
      ;;
  esac
}

emoji_clipboard_dmenu() {
  local prompt="$1"
  local placeholder="$2"

  rofi -dmenu -i -p "${prompt}" -no-show-icons \
    -theme-str "entry { placeholder: \"${placeholder}\";} ${rofi_position} ${r_override}" \
    -theme-str "${font_override}" \
    -theme "$(rofi_resolve_theme clipboard)" -theme-str "${_rofi_opacity}"
}

emoji_extract_skin_tone_modifier() {
  local tone_value="$1"

  case "${tone_value}" in
    *"🏻"*) printf '%s' "🏻" ;;
    *"🏼"*) printf '%s' "🏼" ;;
    *"🏽"*) printf '%s' "🏽" ;;
    *"🏾"*) printf '%s' "🏾" ;;
    *"🏿"*) printf '%s' "🏿" ;;
    *) printf '%s' "" ;;
  esac
}

emoji_filtered_rofi_args() {
  local -n out_args_ref="$1"
  out_args_ref=()
  for arg in "${ROFI_EMOJI_ARGS[@]}"; do
    [[ "${arg}" == "-multi-select" || "${arg}" == "--multi-select" ]] && continue
    out_args_ref+=("${arg}")
  done
}

emoji_selection_menu_args() {
  local style_type="$1"
  local -n rofi_base_opts_ref="$2"
  local -n style_menu_args_ref="$3"
  local -n emoji_args_ref="$4"
  local emoji_theme=""

  emoji_theme="$(rofi_resolve_theme "${ROFI_EMOJI_THEME:-clipboard}")"
  emoji_menu_base_opts "${emoji_theme}" rofi_base_opts_ref
  emoji_style_menu_args "${style_type}" style_menu_args_ref
  emoji_filtered_rofi_args emoji_args_ref
}

emoji_write_selection_source() {
  local target_file="$1"

  {
    if [[ -f "${favorites_data}" ]] && [[ -s "${favorites_data}" ]]; then
      local fav_count
      fav_count=$(wc -l <"${favorites_data}" 2>/dev/null || echo 0)
      if [ "$fav_count" -gt 0 ]; then
        printf '%s\n' "⭐ Favorites (${fav_count} emojis)	:cat:favorites:"
      fi
    fi

    if [[ -f "${recent_data}" ]] && [[ -s "${recent_data}" ]]; then
      local recent_count
      recent_count=$(wc -l <"${recent_data}" 2>/dev/null || echo 0)
      if [ "$recent_count" -gt 0 ]; then
        printf '%s\n' "🕒 Recently Used (${recent_count} emojis)	:cat:recent:"
      fi
    fi

    cat "${emoji_data}"
  } >"${target_file}"
}

emoji_write_display_rows() {
  local source_file="$1"
  local target_file="$2"

  awk -F'\t' '{
    e=$1; l=$2;
    if (l != "" && l !~ /^:cat:/) {
      print e " " l;
    } else {
      print e;
    }
  }' "${source_file}" >"${target_file}"
}

emoji_prepare_selection_workspace() {
  local -n work_dir_ref="$1"
  local -n raw_file_ref="$2"
  local -n display_file_ref="$3"

  work_dir_ref="$(mktemp -d "${TMPDIR:-/tmp}/emoji_select.XXXXXX")" || return 1
  raw_file_ref="${work_dir_ref}/raw"
  display_file_ref="${work_dir_ref}/display"

  emoji_write_selection_source "${raw_file_ref}" || return 1
  emoji_write_display_rows "${raw_file_ref}" "${display_file_ref}" || return 1
}

emoji_selection_raw_line() {
  local raw_file="$1"
  local selection_index="$2"

  awk -v idx=$((selection_index + 1)) 'NR==idx{print;exit}' "${raw_file}"
}

emoji_rofi_selection_index() {
  local display_file="$1"
  shift

  if [[ -n ${use_rofile} ]]; then
    cat "${display_file}" | rofi -dmenu -i -format 'i' "$@" -config "${use_rofile}" \
      -no-show-icons \
      -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
      -no-custom
    return 0
  fi

  cat "${display_file}" | rofi -dmenu -i -format 'i' "$@" \
    -no-show-icons \
    -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
    -theme-str "entry { placeholder: \" 󰞅 Emoji\";} ${rofi_position} ${r_override}" \
    -theme-str "${font_override}" \
    -no-custom
}

emoji_category_source_file() {
  local category="$1"
  local category_file="${emoji_categories_dir}/${category}.db"

  case "${category}" in
    recent)
      if [[ ! -f "${recent_data}" ]] || [[ ! -s "${recent_data}" ]]; then
        dunstify -t 3000 -i "face-smile" "No recently used emojis"
        return 1
      fi
      ;;
    favorites)
      if [[ ! -f "${favorites_data}" ]] || [[ ! -s "${favorites_data}" ]]; then
        dunstify -t 3000 -i "face-smile" "No favorite emojis yet"
        return 1
      fi
      category_file="${favorites_data}"
      ;;
    *)
      if [[ ! -f "${category_file}" ]]; then
        dunstify -t 3000 -i "dialog-error" "Category file not found: ${category}"
        return 1
      fi
      ;;
  esac

  [[ "${category}" == "recent" ]] && category_file="${recent_data}"
  printf '%s\n' "${category_file}"
}

emoji_category_menu_args() {
  local style_type="$1"
  local -n rofi_base_opts_ref="$2"
  local -n style_menu_args_ref="$3"
  local category_theme=""

  case "${style_type}" in
    1 | list | 2 | grid) category_theme="$(rofi_resolve_theme clipboard)" ;;
    *) category_theme="$(rofi_resolve_theme "${style_type:-clipboard}")" ;;
  esac
  emoji_menu_base_opts "${category_theme}" rofi_base_opts_ref
  emoji_style_menu_args "${style_type}" style_menu_args_ref
}

emoji_prepare_category_menu() {
  local category_file="$1"
  local -n work_dir_ref="$2"
  local -n menu_file_ref="$3"

  work_dir_ref="$(mktemp -d "${TMPDIR:-/tmp}/emoji_category.XXXXXX")" || return 1
  menu_file_ref="${work_dir_ref}/menu"
  {
    printf '%s\n' "◀ Back	:b:a:c:k:"
    cat "${category_file}"
  } >"${menu_file_ref}"
}

get_emoji_selection() {
  local style_type="${emoji_style:-${ROFI_EMOJI_STYLE:-2}}"
  local rofi_base_opts=()
  local style_menu_args=()
  local emoji_args=()
  emoji_selection_menu_args "${style_type}" rofi_base_opts style_menu_args emoji_args

  local work_dir=""
  local temp_data=""
  local display_data=""
  emoji_prepare_selection_workspace work_dir temp_data display_data || {
    rm -rf "${work_dir}"
    return 1
  }

  local selection_index=""
  selection_index="$(emoji_rofi_selection_index "${display_data}" "${emoji_args[@]}" "${rofi_base_opts[@]}" "${style_menu_args[@]}")"

  [[ -z "${selection_index}" ]] && {
    rm -rf "${work_dir}"
    return
  }
  local raw_line
  raw_line="$(emoji_selection_raw_line "${temp_data}" "${selection_index}")"
  rm -rf "${work_dir}"
  printf "%s" "${raw_line}"
}

parse_arguments() {
  local usage_text
  usage_text="$(cat <<'HELP'
Usage:
--style [1 | 2]         Change Emoji style
                        Add 'emoji_style=[1|2]' variable in ~/.config/hypr/config.toml'
                            1 = list
                            2 = grid
HELP
)"
  rofi_picker_parse_style_args emoji_style use_rofile "clipboard" "${usage_text}" "$@"
}

# Check if emoji is multi-person and show dual skin tone selector
show_multi_person_skin_tone_selector() {
  local base_emoji="$1"
  if [[ ! "${EMOJI_MULTI_PERSON}" =~ ${base_emoji} ]]; then
    return 1 # Not multi-person
  fi

  # Select Person 1 skin tone
  local tone1
  tone1=$(echo -e "🏾 Medium-Dark\n🏻 Light\n🏼 Medium-Light\n🏽 Medium\n🏿 Dark\nDefault" \
    | emoji_clipboard_dmenu "Person 1 Skin Tone" "Choose skin tone for person 1...")

  [[ -z "${tone1}" ]] && return 1

  # Select Person 2 skin tone
  local tone2
  tone2=$(echo -e "🏾 Medium-Dark\n🏻 Light\n🏼 Medium-Light\n🏽 Medium\n🏿 Dark\nDefault" \
    | emoji_clipboard_dmenu "Person 2 Skin Tone" "Choose skin tone for person 2...")

  [[ -z "${tone2}" ]] && return 1

  # Extract skin tone modifiers
  local modifier1=""
  local modifier2=""
  modifier1="$(emoji_extract_skin_tone_modifier "${tone1}")"
  modifier2="$(emoji_extract_skin_tone_modifier "${tone2}")"

  # Combine emoji with skin tones
  echo "${base_emoji}${modifier1}${modifier2}"

  return 0
}

# Check if emoji has gender variants and show selector
show_gender_variant_selector() {
  local base_emoji="$1"
  if [[ ! "${EMOJI_GENDER_VARIANTS}" =~ ${base_emoji} ]]; then
    return 1 # No gender variants
  fi

  # Show gender selector
  local gender_choice
  gender_choice=$(echo -e "🧑 Person (neutral)\n👨 Man\n👩 Woman" \
    | emoji_clipboard_dmenu "Gender Variant" "Choose gender variant...")

  [[ -z "${gender_choice}" ]] && return 1

  # Return the gendered emoji
  # Most emojis default to neutral (🧑), can add ♂️ or ♀️ via ZWJ
  case "${gender_choice}" in
    *"👨"*)
      echo "${base_emoji}‍♂️"
      ;;
    *"👩"*)
      echo "${base_emoji}‍♀️"
      ;;
    *)
      # Neutral/Person
      echo "${base_emoji}"
      ;;
  esac

  return 0
}

emoji_supports_skin_tone() {
  [[ "${EMOJI_SKIN_TONE_SUPPORTED}" =~ $1 ]]
}

emoji_pick_skin_tone() {
  local base_emoji="$1"

  printf '%s\n' "${EMOJI_SKIN_TONE_MENU}" \
    | sed "s/^/${base_emoji} /" \
    | emoji_clipboard_dmenu "Select Skin Tone" "Choose skin tone..."
}

emoji_finalize_skin_tone() {
  local base_emoji="$1"
  local selected_tone="$2"
  local selected_modifier=""

  selected_modifier="$(emoji_extract_skin_tone_modifier "${selected_tone}")"
  if [[ -n "${selected_modifier}" ]]; then
    echo "${base_emoji}${selected_modifier}"
  elif [[ "${selected_tone}" == *"Default"* ]]; then
    echo "${base_emoji}"
  else
    echo "${base_emoji}🏾"
  fi
}

# Check if emoji supports skin tones and show selection menu
show_skin_tone_selector() {
  local base_emoji="$1"
  local selected_tone=""

  local gendered_emoji
  if gendered_emoji=$(show_gender_variant_selector "${base_emoji}"); then
    base_emoji="${gendered_emoji}"
  fi

  if show_multi_person_skin_tone_selector "${base_emoji}"; then
    return 0
  fi

  if ! emoji_supports_skin_tone "${base_emoji}"; then
    echo "${base_emoji}"
    return
  fi

  selected_tone="$(emoji_pick_skin_tone "${base_emoji}")"
  emoji_finalize_skin_tone "${base_emoji}" "${selected_tone}"
}

# Show category sub-menu
show_category_menu() {
  local category="$1"
  local category_file=""
  category_file="$(emoji_category_source_file "${category}")" || return 1

  local work_dir=""
  local temp_category=""
  emoji_prepare_category_menu "${category_file}" work_dir temp_category || {
    rm -rf "${work_dir}"
    return 1
  }

  local selected
  local style_type="${emoji_style:-${ROFI_EMOJI_STYLE:-2}}"
  local rofi_base_opts=()
  local style_menu_args=()
  emoji_category_menu_args "${style_type}" rofi_base_opts style_menu_args

  selected=$(cat "${temp_category}" | rofi -dmenu -i "${style_menu_args[@]}" \
    -no-show-icons "${rofi_base_opts[@]}" \
    -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
    -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
    -theme-str "${font_override}" \
    -no-custom)

  rm -rf "${work_dir}"
  echo "${selected}"
}

ensure_emoji_runtime_files() {
  if [[ ! -f "${recent_data}" ]]; then
    mkdir -p "$(dirname "${recent_data}")"
    touch "${recent_data}"
  fi
  clean_emoji_file "${recent_data}"
  clean_emoji_file "${favorites_data}"
}

emoji_selection_category() {
  [[ "$1" =~ :cat:([a-z]+):$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

emoji_normalize_selection_record() {
  if [[ "$1" == *$'\t'* ]]; then
    printf '%s\n' "$1"
    return 0
  fi

  local emoji_token desc_token
  emoji_token="${1%% *}"
  desc_token="${1#${emoji_token}}"
  desc_token="${desc_token# }"
  printf '%s\t%s\n' "${emoji_token}" "${desc_token}"
}

emoji_pick_record() {
  local selection=""
  local category=""

  selection="$(get_emoji_selection)"
  while [[ -n "${selection}" ]]; do
    category="$(emoji_selection_category "${selection}" 2>/dev/null || true)"
    [[ -n "${category}" ]] || break

    selection="$(show_category_menu "${category}")"
    [[ -n "${selection}" ]] || return 1
    [[ "${selection}" =~ :b:a:c:k:$ ]] && selection="$(get_emoji_selection)"
  done

  [[ -n "${selection}" ]] || return 1
  emoji_normalize_selection_record "${selection}"
}

emoji_apply_selection() {
  local selection_record="$1"
  local selected_emoji_char=""
  local selected_desc=""
  local final_emoji=""

  selected_emoji_char=$(printf "%s" "${selection_record}" | cut -d$'\t' -f1 | xargs)
  selected_desc=$(printf "%s" "${selection_record}" | cut -d$'\t' -f2- | xargs)
  [[ -n "${selected_emoji_char}" ]] || return 0

  final_emoji=$(show_skin_tone_selector "${selected_emoji_char}" "${selected_desc}")
  [[ -n "${final_emoji}" ]] || return 0

  wl-copy "${final_emoji}"
  save_recent_entry "${final_emoji}"$'\t'"${selected_desc}"
  [[ "${EMOJI_AUTO_PASTE:-1}" == "0" ]] || paste_string "${@}"
}

main() {
  local data_emoji=""

  parse_arguments "$@"
  ensure_emoji_runtime_files
  setup_rofi_config
  data_emoji="$(emoji_pick_record)" || exit 0
  emoji_apply_selection "${data_emoji}" "${@}"
}

main "$@"
