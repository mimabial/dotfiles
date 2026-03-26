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

clean_emoji_file() {
  local target_file="$1"
  [[ ! -f "${target_file}" ]] && return
  local tmp
  tmp=$(mktemp)
  awk -F'\t' 'BEGIN{OFS="\t"}{
    e=$1; d=$2;
    gsub(/\xf0\x9f\xb3\xbb|\xf0\x9f\xb3\xbc|\xf0\x9f\xb3\xbd|\xf0\x9f\xb3\xbe|\xf0\x9f\xb3\xbf/,"",e);
    if (d ~ "^" e " ") sub("^" e " ","",d);
    if (!seen[e]++) print e,d;
  }' "${target_file}" >"${tmp}" && mv "${tmp}" "${target_file}"
}

save_recent_entry() {
  local emoji_line="$1"
  local recent_dir=""
  local tmp_file=""
  emoji_line=$(printf "%s" "${emoji_line}" | sed 's/\\([\U0001F3FB-\U0001F3FF]\\)//g')
  mkdir -p "$(dirname "${recent_data}")"
  recent_dir="$(dirname "${recent_data}")"
  tmp_file="$(mktemp "${recent_dir}/.emoji_recent.XXXXXX")"
  {
    echo "${emoji_line}"
    cat "${recent_data}" 2>/dev/null
  } | awk '!seen[$0]++' | head -50 >"${tmp_file}" && mv "${tmp_file}" "${recent_data}"
}

toggle_favorite() {
  local emoji_line="$1"
  local favorites_dir=""
  local tmp_file=""
  mkdir -p "$(dirname "${favorites_data}")"
  favorites_dir="$(dirname "${favorites_data}")"

  # Check if already favorited
  if grep -Fxq "${emoji_line}" "${favorites_data}" 2>/dev/null; then
    # Remove from favorites
    tmp_file="$(mktemp "${favorites_dir}/.favorites.XXXXXX")"
    grep -Fxv "${emoji_line}" "${favorites_data}" >"${tmp_file}" && mv "${tmp_file}" "${favorites_data}"
    dunstify -t 3000 -i "face-smile" "⭐ Removed from favorites"
  else
    # Add to favorites
    echo "${emoji_line}" >>"${favorites_data}"
    dunstify -t 3000 -i "face-smile" "⭐ Added to favorites"
  fi
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

  local emoji_window_width_px
  emoji_window_width_px="$(rofi_length_em_to_px "${emoji_window_width_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${emoji_window_width_px}" =~ ^[0-9]+$ ]] || emoji_window_width_px=$((81 * font_scale))
  local emoji_window_height_px
  emoji_window_height_px="$(rofi_length_em_to_px "${emoji_window_height_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${emoji_window_height_px}" =~ ^[0-9]+$ ]] || emoji_window_height_px=$((60 * font_scale))

  rofi_position=$(get_rofi_pos "${emoji_window_width_px}" "${emoji_window_height_px}")
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

get_emoji_selection() {
  local style_type="${emoji_style:-${ROFI_EMOJI_STYLE:-2}}"
  local emoji_theme
  emoji_theme="$(rofi_resolve_theme "${ROFI_EMOJI_THEME:-clipboard}")"
  local rofi_base_opts=()
  local style_menu_args=()
  emoji_menu_base_opts "${emoji_theme}" rofi_base_opts
  emoji_style_menu_args "${style_type}" style_menu_args
  local emoji_args=()
  for arg in "${ROFI_EMOJI_ARGS[@]}"; do
    [[ "${arg}" == "-multi-select" || "${arg}" == "--multi-select" ]] && continue
    emoji_args+=("${arg}")
  done

  # Create recently used and favorites category entries
  local temp_dir="${TMPDIR:-/tmp}"
  local temp_data=""
  local display_data=""
  temp_data="$(mktemp "${temp_dir}/emoji_with_raw.XXXXXX")" || return 1
  display_data="$(mktemp "${temp_dir}/emoji_display.XXXXXX")" || {
    rm -f "${temp_data}"
    return 1
  }

  # Add favorites category if favorites exist
  if [[ -f "${favorites_data}" ]] && [[ -s "${favorites_data}" ]]; then
    local fav_count=$(wc -l <"${favorites_data}" 2>/dev/null || echo 0)
    if [ "$fav_count" -gt 0 ]; then
      echo "⭐ Favorites (${fav_count} emojis)	:cat:favorites:" >"${temp_data}"
    fi
  fi

  # Add recently used category if recent data exists
  if [[ -f "${recent_data}" ]] && [[ -s "${recent_data}" ]]; then
    local recent_count=$(wc -l <"${recent_data}" 2>/dev/null || echo 0)
    if [ "$recent_count" -gt 0 ]; then
      echo "🕒 Recently Used (${recent_count} emojis)	:cat:recent:" >>"${temp_data}"
    fi
  fi

  cat "${emoji_data}" >>"${temp_data}"

  # Build display strings (emoji + label if present and not a category marker), strip variation selectors for display
  awk -F'\t' '{
    e=$1; l=$2;
    if (l != "" && l !~ /^:cat:/) {
      print e " " l;
    } else {
      print e;
    }
  }' "${temp_data}" >"${display_data}"

  local selection_index=""
  if [[ -n ${use_rofile} ]]; then
    selection_index=$(cat "${display_data}" | rofi -dmenu -i -format 'i' "${emoji_args[@]}" "${rofi_base_opts[@]}" -config "${use_rofile}" \
      -no-show-icons \
      -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
      -no-custom)
  else
    selection_index=$(cat "${display_data}" | rofi -dmenu -i -format 'i' "${emoji_args[@]}" "${rofi_base_opts[@]}" "${style_menu_args[@]}" \
      -no-show-icons \
      -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
      -theme-str "entry { placeholder: \" 󰞅 Emoji\";} ${rofi_position} ${r_override}" \
      -theme-str "${font_override}" \
      -no-custom)
  fi

  rm -f "${display_data}"

  [[ -z "${selection_index}" ]] && {
    rm -f "${temp_data}"
    return
  }
  # rofi returns 0-based index; fetch raw line (keeps category markers)
  local raw_line
  raw_line=$(awk -v idx=$((selection_index + 1)) 'NR==idx{print;exit}' "${temp_data}")
  rm -f "${temp_data}"
  printf "%s" "${raw_line}"
}

parse_arguments() {
  while (($# > 0)); do
    case $1 in
      --style | -s)
        if (($# > 1)); then
          emoji_style="$2"
          shift
        else
          print_log +y "[warn] " "--style needs argument"
          emoji_style="clipboard"
          shift
        fi
        ;;
      --rasi)
        [[ -z ${2} ]] && print_log +r "[error] " +y "--rasi requires an file.rasi config file" && exit 1
        use_rofile=${2}
        shift
        ;;
      -*)
        cat <<HELP
Usage:
--style [1 | 2]         Change Emoji style
                        Add 'emoji_style=[1|2]' variable in ~/.config/hypr/config.toml'
                            1 = list
                            2 = grid
HELP

        exit 0
        ;;
    esac
    shift
  done
}

# Check if emoji is multi-person and show dual skin tone selector
show_multi_person_skin_tone_selector() {
  local base_emoji="$1"

  # Multi-person emojis that support dual skin tones
  local multi_person="🤝👫👬👭🧑‍🤝‍🧑💑👩‍❤️‍👨👨‍❤️‍👨👩‍❤️‍👩🧑‍❤️‍🧑💏👩‍❤️‍💋‍👨👨‍❤️‍💋‍👨👩‍❤️‍💋‍👩🧑‍❤️‍💋‍🧑"

  if [[ ! "${multi_person}" =~ ${base_emoji} ]]; then
    return 1 # Not multi-person
  fi

  # Select Person 1 skin tone
  local tone1
  tone1=$(echo -e "🏾 Medium-Dark\n🏻 Light\n🏼 Medium-Light\n🏽 Medium\n🏿 Dark\nDefault" \
    | rofi -dmenu -i -p "Person 1 Skin Tone" -no-show-icons \
      -theme-str "entry { placeholder: \"Choose skin tone for person 1...\";} ${rofi_position} ${r_override}" \
      -theme-str "${font_override}" \
      -theme "$(rofi_resolve_theme clipboard)" -theme-str "${_rofi_opacity}")

  [[ -z "${tone1}" ]] && return 1

  # Select Person 2 skin tone
  local tone2
  tone2=$(echo -e "🏾 Medium-Dark\n🏻 Light\n🏼 Medium-Light\n🏽 Medium\n🏿 Dark\nDefault" \
    | rofi -dmenu -i -p "Person 2 Skin Tone" -no-show-icons \
      -theme-str "entry { placeholder: \"Choose skin tone for person 2...\";} ${rofi_position} ${r_override}" \
      -theme-str "${font_override}" \
      -theme "$(rofi_resolve_theme clipboard)" -theme-str "${_rofi_opacity}")

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

  # Emojis that have gender variants (person → man/woman)
  # These use ZWJ sequences: base + ZWJ + ♂️/♀️
  local gender_variants="🧑👱🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵️💂🥷👷🤴👸👳👲🧕🤵👰🦸🦹🧙🧚🧛🧜🧝🧞💆💇🚶🧍🧎🏃🕺💃🧖🧗🤸🏌️🏄🚣🏊⛹️🏋️🚴🚵🤽🤾🤹🧘🧑‍🎓🧑‍🏫🧑‍⚕️🧑‍🌾🧑‍🍳🧑‍🔧🧑‍🏭🧑‍💼🧑‍🔬🧑‍💻🧑‍🎤🧑‍🎨🧑‍✈️🧑‍🚀🧑‍🚒🧑‍🦯🧑‍🦼🧑‍🦽"

  # Check if this emoji has gender variants
  if [[ ! "${gender_variants}" =~ ${base_emoji} ]]; then
    return 1 # No gender variants
  fi

  # Show gender selector
  local gender_choice
  gender_choice=$(echo -e "🧑 Person (neutral)\n👨 Man\n👩 Woman" \
    | rofi -dmenu -i -p "Gender Variant" \
      -theme-str "entry { placeholder: \"Choose gender variant...\";} ${rofi_position} ${r_override}" \
      -theme-str "${font_override}" \
      -theme "$(rofi_resolve_theme clipboard)" -theme-str "${_rofi_opacity}")

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

# Check if emoji supports skin tones and show selection menu
show_skin_tone_selector() {
  local base_emoji="$1"
  local base_description="$2"

  # First check if it has gender variants
  local gendered_emoji
  if gendered_emoji=$(show_gender_variant_selector "${base_emoji}"); then
    base_emoji="${gendered_emoji}"
  fi

  # Then check if it's multi-person
  if show_multi_person_skin_tone_selector "${base_emoji}"; then
    return 0
  fi

  # List of emojis that support skin tones (hands, people, body parts)
  local skin_tone_supported="👋🤚🖐️✋🖖🫱🫲🫳🫴🫷🫸👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆🫵👇☝️👍👎✊👊🤛🤜👏🙌🫶👐🤲🙏✍️💅🤳💪🦵🦶👂🦻👃🫦🧒👦👧🧑👱👨👩🧔👴👵🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵️💂🥷👷🫅🤴👸👳👲🧕🤵👰🤰🫄🫃🤱👼🎅🤶🧑‍🎄🦸🦹🧙🧚🧛🧜🧝🧞🧟💆💇🚶🧍🧎🏃💃🕺🕴️👯🧖🧗🤺🏇⛷️🏂🏌️🏄🚣🏊⛹️🏋️🚴🚵🤸🤼🤽🤾🤹🛀🛌🧘"

  # Check if emoji supports skin tones
  if [[ ! "${skin_tone_supported}" =~ ${base_emoji} ]]; then
    echo "${base_emoji}"
    return
  fi

  # Show skin tone selection menu with actual rendered emojis
  local selected_tone
  selected_tone=$(printf "${base_emoji} Default\n${base_emoji}🏿 Dark\n${base_emoji}🏾 Medium-Dark\n${base_emoji}🏽 Medium\n${base_emoji}🏼 Medium-Light\n${base_emoji}🏻 Light" \
    | rofi -dmenu -i -p "Select Skin Tone" \
      -theme-str "entry { placeholder: \"Choose skin tone...\";} ${rofi_position} ${r_override}" \
      -theme-str "${font_override}" \
      -theme "$(rofi_resolve_theme clipboard)" -theme-str "${_rofi_opacity}")

  # Extract just the skin tone part from selection
  local selected_modifier=""
  selected_modifier="$(emoji_extract_skin_tone_modifier "${selected_tone}")"
  if [[ -n "${selected_modifier}" ]]; then
    echo "${base_emoji}${selected_modifier}"
  elif [[ "${selected_tone}" == *"Default"* ]]; then
    echo "${base_emoji}"
  else
    # User cancelled, use medium-dark as default
    echo "${base_emoji}🏾"
  fi
}

# Show category sub-menu
show_category_menu() {
  local category="$1"
  local category_file="${emoji_categories_dir}/${category}.db"

  # Handle special categories
  if [[ "${category}" == "recent" ]]; then
    if [[ ! -f "${recent_data}" ]] || [[ ! -s "${recent_data}" ]]; then
      dunstify -t 3000 -i "face-smile" "No recently used emojis"
      return 1
    fi
    category_file="${recent_data}"
  elif [[ "${category}" == "favorites" ]]; then
    if [[ ! -f "${favorites_data}" ]] || [[ ! -s "${favorites_data}" ]]; then
      dunstify -t 3000 -i "face-smile" "No favorite emojis yet"
      return 1
    fi
    category_file="${favorites_data}"
  elif [[ ! -f "${category_file}" ]]; then
    dunstify -t 3000 -i "dialog-error" "Category file not found: ${category}"
    return 1
  fi

  # Add back navigation option
  local temp_dir="${TMPDIR:-/tmp}"
  local temp_category=""
  temp_category="$(mktemp "${temp_dir}/emoji_category.XXXXXX")" || return 1
  echo "◀ Back	:b:a:c:k:" >"${temp_category}"
  cat "${category_file}" >>"${temp_category}"

  # Show category-specific emoji menu
  local selected
  local style_type="${emoji_style:-${ROFI_EMOJI_STYLE:-2}}"
  local category_theme=""
  local rofi_base_opts=()
  local style_menu_args=()

  case "${style_type}" in
    1 | list | 2 | grid) category_theme="$(rofi_resolve_theme clipboard)" ;;
    *) category_theme="$(rofi_resolve_theme "${style_type:-clipboard}")" ;;
  esac
  emoji_menu_base_opts "${category_theme}" rofi_base_opts
  emoji_style_menu_args "${style_type}" style_menu_args

  selected=$(cat "${temp_category}" | rofi -dmenu -i "${style_menu_args[@]}" \
    -no-show-icons "${rofi_base_opts[@]}" \
    -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
    -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
    -theme-str "${font_override}" \
    -no-custom)

  rm -f "${temp_category}"
  echo "${selected}"
}

main() {
  parse_arguments "$@"

  if [[ ! -f "${recent_data}" ]]; then
    mkdir -p "$(dirname "${recent_data}")"
    touch "${recent_data}"
  fi
  clean_emoji_file "${recent_data}"
  clean_emoji_file "${favorites_data}"

  setup_rofi_config

  data_emoji=$(get_emoji_selection)

  # Empty selection (Esc) on main menu exits; on category, go back
  if [[ -z "${data_emoji}" ]]; then
    exit 0
  fi

  # Check for a category marker at the end of the selection payload.
  if [[ "${data_emoji}" =~ :cat:([a-z]+):$ ]]; then
    local category="${BASH_REMATCH[1]}"
    data_emoji=$(show_category_menu "${category}")
    # Esc in category: go back to main menu
    [[ -z "${data_emoji}" ]] && {
      main "$@"
      exit 0
    }

    # Handle back navigation from category menu
    if [[ "${data_emoji}" =~ :b:a:c:k:$ ]]; then
      main "$@"
      exit 0
    fi
  fi

  # Normalize selections without tab (category files are space-separated)
  if [[ "${data_emoji}" != *$'\t'* ]]; then
    local emoji_token desc_token
    emoji_token="${data_emoji%% *}"
    desc_token="${data_emoji#${emoji_token}}"
    desc_token="${desc_token# }"
    data_emoji="${emoji_token}"$'\t'"${desc_token}"
  fi

  local selected_emoji_char=""
  local selected_desc=""
  selected_emoji_char=$(printf "%s" "${data_emoji}" | cut -d$'\t' -f1 | xargs)
  selected_desc=$(printf "%s" "${data_emoji}" | cut -d$'\t' -f2- | xargs)

  if [[ -n "${selected_emoji_char}" ]]; then
    # Check if emoji supports skin tones and show selector
    local final_emoji
    final_emoji=$(show_skin_tone_selector "${selected_emoji_char}" "${selected_desc}")

    [[ -z "${final_emoji}" ]] && exit 0

    wl-copy "${final_emoji}"
    save_recent_entry "${final_emoji}"$'\t'"${selected_desc}"

    # Only paste if EMOJI_AUTO_PASTE is not set to 0
    if [[ "${EMOJI_AUTO_PASTE:-1}" != "0" ]]; then
      paste_string "${@}"
    fi
  fi
}

main "$@"
