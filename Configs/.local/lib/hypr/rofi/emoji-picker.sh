#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HOME}/.local/lib/hypr/rofi/picker.common.bash"
rofi_picker_bootstrap || exit 1

emoji_dir=""
cache_dir=""
font_override=""
r_override=""
rofi_position=""
emoji_window_theme=""
_rofi_opacity=""
rofi_picker_hypr_dir_vars emoji_dir cache_dir
emoji_data="${emoji_dir}/emoji.db"
emoji_categories_dir="${emoji_dir}/emoji-categories"
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
    "${ROFI_EMOJI_SCALE:-}" "${ROFI_EMOJI_FONT:-${ROFI_FONT:-}}" wallbox same

  local emoji_window_width_em="${ROFI_EMOJI_WIDTH_EM:-36}"
  local emoji_window_height_em="${ROFI_EMOJI_HEIGHT_EM:-30}"
  [[ "${emoji_window_width_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || emoji_window_width_em="40.5"
  [[ "${emoji_window_height_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || emoji_window_height_em="30"

  rofi_picker_compute_window_geometry \
    rofi_position emoji_window_theme \
    "${font_name}" "${font_scale}" \
    "${emoji_window_width_em}" "${emoji_window_height_em}" \
    $((81 * font_scale)) $((60 * font_scale))
}

emoji_menu_base_opts() {
  local theme_name="$1"
  local -n opts_ref="$2"

  opts_ref=(-no-config -no-default-config -theme "${theme_name}")
  [[ -n "${emoji_window_theme:-}" ]] && opts_ref+=("-theme-str" "${emoji_window_theme}")
  [[ -n "${_rofi_opacity:-}" ]] && opts_ref+=("-theme-str" "${_rofi_opacity}")
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
    -theme-str "${emoji_window_theme}" \
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
  # shellcheck disable=SC2034 # Nameref output assigned for the caller.
  out_args_ref=()
  for arg in "${ROFI_EMOJI_ARGS[@]}"; do
    [[ "${arg}" == "-multi-select" || "${arg}" == "--multi-select" ]] && continue
    out_args_ref+=("${arg}")
  done
}

emoji_selection_menu_args() {
  local style_type="$1"
  local rofi_base_opts_name="$2"
  local style_menu_args_name="$3"
  local emoji_args_name="$4"
  local emoji_theme=""

  emoji_theme="$(rofi_resolve_theme "${ROFI_EMOJI_THEME:-clipboard}")"
  emoji_menu_base_opts "${emoji_theme}" "${rofi_base_opts_name}"
  emoji_style_menu_args "${style_type}" "${style_menu_args_name}"
  emoji_filtered_rofi_args "${emoji_args_name}"
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

    rofi_picker_recent_category_entry "${recent_data}" "🕒" "Recently Used" "emojis" || true

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

emoji_rofi_selection_index() {
  local display_file="$1"
  local -a rofi_config_args=()
  shift

  if [[ -n ${use_rofile} ]]; then
    rofi_picker_rasi_args rofi_config_args "${use_rofile}" "${rofi_position}"
    rofi -dmenu -i -format 'i' "$@" "${rofi_config_args[@]}" \
      -no-show-icons \
      -theme-str "${emoji_window_theme}" \
      -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
      -no-custom <"${display_file}"
    return 0
  fi

  rofi -dmenu -i -format 'i' "$@" \
    -no-show-icons \
    -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
    -theme-str "entry { placeholder: \" 󰞅 Emoji\";} ${rofi_position} ${r_override}" \
    -theme-str "${font_override}" \
    -theme-str "${emoji_window_theme}" \
    -no-custom <"${display_file}"
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
  local rofi_base_opts_name="$2"
  local style_menu_args_name="$3"
  local category_theme=""

  case "${style_type}" in
    1 | list | 2 | grid) category_theme="$(rofi_resolve_theme clipboard)" ;;
    *) category_theme="$(rofi_resolve_theme "${style_type:-clipboard}")" ;;
  esac
  emoji_menu_base_opts "${category_theme}" "${rofi_base_opts_name}"
  emoji_style_menu_args "${style_type}" "${style_menu_args_name}"
}

emoji_prepare_category_menu() {
  local category_file="$1"
  local work_dir_name="$2"
  local menu_file_name="$3"
  local work_dir=""
  local menu_file=""

  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/emoji_category.XXXXXX")" || return 1
  menu_file="${work_dir}/menu"
  printf -v "${work_dir_name}" '%s' "${work_dir}"
  printf -v "${menu_file_name}" '%s' "${menu_file}"
  {
    printf '%s\n' "◀ Back	:b:a:c:k:"
    cat "${category_file}"
  } >"${menu_file}"
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
  raw_line="$(rofi_picker_index_to_line "${temp_data}" "${selection_index}")"
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

show_multi_person_skin_tone_selector() {
  local base_emoji="$1"
  if [[ ! "${EMOJI_MULTI_PERSON}" =~ ${base_emoji} ]]; then
    return 1 # Not multi-person
  fi

  # Person 1 menu: preview as <base><modifier> so each row shows the colored
  # base emoji rather than a bare tone square.
  local tone1
  tone1=$(printf '%s\n' "${base_emoji}🏾 Medium-Dark" "${base_emoji}🏻 Light" \
      "${base_emoji}🏼 Medium-Light" "${base_emoji}🏽 Medium" \
      "${base_emoji}🏿 Dark" "${base_emoji} Default" \
    | emoji_clipboard_dmenu "Person 1 Skin Tone" "Choose skin tone for person 1...")

  [[ -z "${tone1}" ]] && return 1
  local modifier1=""
  modifier1="$(emoji_extract_skin_tone_modifier "${tone1}")"

  # Person 2 menu: preview composed with person 1's pick so the row shows the
  # final two-tone emoji that will be produced.
  local tone2
  tone2=$(printf '%s\n' "${base_emoji}${modifier1}🏾 Medium-Dark" "${base_emoji}${modifier1}🏻 Light" \
      "${base_emoji}${modifier1}🏼 Medium-Light" "${base_emoji}${modifier1}🏽 Medium" \
      "${base_emoji}${modifier1}🏿 Dark" "${base_emoji}${modifier1} Default" \
    | emoji_clipboard_dmenu "Person 2 Skin Tone" "Choose skin tone for person 2...")

  [[ -z "${tone2}" ]] && return 1
  local modifier2=""
  modifier2="$(emoji_extract_skin_tone_modifier "${tone2}")"

  echo "${base_emoji}${modifier1}${modifier2}"

  return 0
}

show_gender_variant_selector() {
  local base_emoji="$1"
  if [[ ! "${EMOJI_GENDER_VARIANTS}" =~ ${base_emoji} ]]; then
    return 1 # No gender variants
  fi

  local gender_choice
  gender_choice=$(echo -e "🧑 Person (neutral)\n👨 Man\n👩 Woman" \
    | emoji_clipboard_dmenu "Gender Variant" "Choose gender variant...")

  [[ -z "${gender_choice}" ]] && return 1

  # Most emojis default to neutral (🧑), can add ♂️ or ♀️ via ZWJ
  case "${gender_choice}" in
    *"👨"*)
      echo "${base_emoji}‍♂️"
      ;;
    *"👩"*)
      echo "${base_emoji}‍♀️"
      ;;
    *)
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

  # Compose each menu entry as <base><modifier> <label> so Unicode skin-tone
  # composition produces the actual colored emoji in the preview, rather than
  # showing the base, a space, and a bare tone square.
  printf '%s\n' "${EMOJI_SKIN_TONE_MENU}" \
    | awk -v base="${base_emoji}" '
        /^Default$/ { print base " " $0; next }
        { print base $0 }
      ' \
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

  selected=$(rofi -dmenu -i "${style_menu_args[@]}" \
    -no-show-icons "${rofi_base_opts[@]}" \
    -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
    -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
    -theme-str "${font_override}" \
    -no-custom <"${temp_category}")

  rm -rf "${work_dir}"
  echo "${selected}"
}

ensure_emoji_runtime_files() {
  rofi_picker_prepare_data_file "${recent_data}" clean_emoji_file
  rofi_picker_prepare_data_file "${favorites_data}" clean_emoji_file
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
  desc_token="${1#"${emoji_token}"}"
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
