#!/usr/bin/env bash

pkill -u "$USER" rofi && exit 0

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

emoji_dir=${HYPR_CONFIG_HOME:-$HOME/.config/hypr}
emoji_data="${emoji_dir}/emoji.db"
emoji_categories_dir="${emoji_dir}/emoji-categories"
cache_dir="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}"
recent_data="${cache_dir}/landing/show_emoji.recent"
favorites_data="${cache_dir}/landing/emoji_favorites"

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
  emoji_line=$(printf "%s" "${emoji_line}" | sed 's/\\([\U0001F3FB-\U0001F3FF]\\)//g')
  mkdir -p "$(dirname "${recent_data}")"
  {
    echo "${emoji_line}"
    cat "${recent_data}" 2>/dev/null
  } | awk '!seen[$0]++' | head -50 >temp && mv temp "${recent_data}"
}

toggle_favorite() {
  local emoji_line="$1"
  mkdir -p "$(dirname "${favorites_data}")"

  # Check if already favorited
  if grep -Fxq "${emoji_line}" "${favorites_data}" 2>/dev/null; then
    # Remove from favorites
    grep -Fxv "${emoji_line}" "${favorites_data}" >temp && mv temp "${favorites_data}"
    notify-send "⭐ Removed from favorites"
  else
    # Add to favorites
    echo "${emoji_line}" >>"${favorites_data}"
    notify-send "⭐ Added to favorites"
  fi
}

setup_rofi_config() {
  local font_scale="${ROFI_EMOJI_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  local font_name=${ROFI_EMOJI_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  font_override="* {font: \"${font_name} ${font_scale}\";}"

  local hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
  local wind_border=$((hypr_border * 3 / 2))
  # local elem_border=$((hypr_border == 0 ? 5 : hypr_border))
  local elem_border=${hypr_border}

  # get_rofi_pos will auto-calculate clipboard theme dimensions based on ROFI_SCALE
  rofi_position=$(get_rofi_pos)

  local hypr_width=${hypr_width:-"$(hyprctl -j getoption general:border_size | jq '.int')"}
  r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;}listview{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"
}

get_emoji_selection() {
  local style_type="${emoji_style:-$ROFI_EMOJI_STYLE}"
  local size_override=""
  local iconless_theme_str="listview { show-icons: false; } element { children: [ \"element-text\" ]; } element-icon { enabled: false; size: 0em; width: 0em; padding: 0; margin: 0; border: 0; }"
  local emoji_theme="${ROFI_EMOJI_THEME:-clipboard}"
  local rofi_base_opts=(-no-config -no-default-config -theme "${emoji_theme}")
  local emoji_args=()
  for arg in "${ROFI_EMOJI_ARGS[@]}"; do
    [[ "${arg}" == "-multi-select" || "${arg}" == "--multi-select" ]] && continue
    emoji_args+=("${arg}")
  done

  # Create recently used and favorites category entries
  local temp_data="/tmp/emoji_with_raw_$$"
  local display_data="/tmp/emoji_display_$$"

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
    gsub(/\ufe0f/,"",e);
    gsub(/\ufe0f/,"",l);
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
      -theme-str "${iconless_theme_str}" \
      -no-custom)
  else
    case ${style_type} in
      2 | grid)
        selection_index=$(cat "${display_data}" | rofi -dmenu -i -format 'i' "${emoji_args[@]}" "${rofi_base_opts[@]}" -display-columns 1 \
          -no-show-icons \
          -theme-str "${iconless_theme_str}" \
          -theme-str "listview {columns: 9;}" \
          -theme-str "entry { placeholder: \"  Emoji\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "${size_override}" \
          -no-custom)
        ;;
      1 | list)
        selection_index=$(cat "${display_data}" | rofi -dmenu -i -format 'i' "${emoji_args[@]}" "${rofi_base_opts[@]}" \
          -display-columns 1 -no-show-icons \
          -theme-str "${iconless_theme_str}" \
          -theme-str "entry { placeholder: \"  Emoji\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -no-custom)
        ;;
      *)
        selection_index=$(cat "${display_data}" | rofi -dmenu -i -format 'i' "${emoji_args[@]}" "${rofi_base_opts[@]}" \
          -display-columns 1 -no-show-icons \
          -theme-str "${iconless_theme_str}" \
          -theme-str "entry { placeholder: \" 🔎 Emoji\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -no-custom)
        ;;
    esac
  fi

  rm -f "${display_data}"

  [[ -z "${selection_index}" ]] && { rm -f "${temp_data}"; return; }
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
                        or select styles from 'rofi-theme-selector'
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
      -theme "clipboard")

  [[ -z "${tone1}" ]] && return 1

  # Select Person 2 skin tone
  local tone2
  tone2=$(echo -e "🏾 Medium-Dark\n🏻 Light\n🏼 Medium-Light\n🏽 Medium\n🏿 Dark\nDefault" \
    | rofi -dmenu -i -p "Person 2 Skin Tone" -no-show-icons \
      -theme-str "entry { placeholder: \"Choose skin tone for person 2...\";} ${rofi_position} ${r_override}" \
      -theme-str "${font_override}" \
      -theme "clipboard")

  [[ -z "${tone2}" ]] && return 1

  # Extract skin tone modifiers
  local modifier1=""
  local modifier2=""

  case "${tone1}" in
    *"🏻"*) modifier1="🏻" ;;
    *"🏼"*) modifier1="🏼" ;;
    *"🏽"*) modifier1="🏽" ;;
    *"🏾"*) modifier1="🏾" ;;
    *"🏿"*) modifier1="🏿" ;;
  esac

  case "${tone2}" in
    *"🏻"*) modifier2="🏻" ;;
    *"🏼"*) modifier2="🏼" ;;
    *"🏽"*) modifier2="🏽" ;;
    *"🏾"*) modifier2="🏾" ;;
    *"🏿"*) modifier2="🏿" ;;
  esac

  # Combine emoji with skin tones
  # For handshake: 🤝 + tone1 + tone2
  # For holding hands with ZWJ: emoji + tone1 + ZWJ + tone2
  if [[ "${base_emoji}" == "🤝" ]]; then
    echo "${base_emoji}${modifier1}${modifier2}"
  else
    # For complex emojis with ZWJ, insert tones appropriately
    echo "${base_emoji}${modifier1}${modifier2}"
  fi

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
      -theme "clipboard")

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
      -theme "clipboard")

  # Extract just the skin tone part from selection
  if [[ "${selected_tone}" == *"🏻"* ]]; then
    echo "${base_emoji}🏻"
  elif [[ "${selected_tone}" == *"🏼"* ]]; then
    echo "${base_emoji}🏼"
  elif [[ "${selected_tone}" == *"🏽"* ]]; then
    echo "${base_emoji}🏽"
  elif [[ "${selected_tone}" == *"🏾"* ]]; then
    echo "${base_emoji}🏾"
  elif [[ "${selected_tone}" == *"🏿"* ]]; then
    echo "${base_emoji}🏿"
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
      notify-send "No recently used emojis"
      return 1
    fi
    category_file="${recent_data}"
  elif [[ "${category}" == "favorites" ]]; then
    if [[ ! -f "${favorites_data}" ]] || [[ ! -s "${favorites_data}" ]]; then
      notify-send "No favorite emojis yet"
      return 1
    fi
    category_file="${favorites_data}"
  elif [[ ! -f "${category_file}" ]]; then
    notify-send "Category file not found: ${category}"
    return 1
  fi

  # Add back navigation option
  local temp_category="/tmp/emoji_category_$$"
  echo "◀ Back	:b:a:c:k:" >"${temp_category}"
  cat "${category_file}" >>"${temp_category}"

  # Show category-specific emoji menu
  local selected
  local style_type="${emoji_style:-$ROFI_EMOJI_STYLE}"

  case ${style_type} in
    2 | grid)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -display-column-separator " " -no-show-icons "${rofi_base_opts[@]}" \
        -theme-str "${iconless_theme_str}" \
        -theme-str "listview {columns: 9;}" \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "clipboard" \
        -no-custom)
      ;;
    1 | list)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -no-show-icons "${rofi_base_opts[@]}" \
        -theme-str "${iconless_theme_str}" \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "clipboard" \
        -no-custom)
      ;;
    *)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -no-show-icons "${rofi_base_opts[@]}" \
        -theme-str "${iconless_theme_str}" \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "${style_type:-clipboard}" \
        -no-custom)
      ;;
  esac

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

  # Check if it's a category selection (marker is at the end now)
  if [[ "${data_emoji}" =~ :cat:([a-z]+):$ ]]; then
    local category="${BASH_REMATCH[1]}"
    data_emoji=$(show_category_menu "${category}")
    # Esc in category: go back to main menu
    [[ -z "${data_emoji}" ]] && { main "$@"; exit 0; }

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
