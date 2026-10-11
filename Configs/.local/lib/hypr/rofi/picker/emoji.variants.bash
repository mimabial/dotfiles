#!/usr/bin/env bash

EMOJI_VARIATION_SELECTOR=$'\uFE0F'
EMOJI_SKIN_TONES=(🏿 🏾 🏽 🏼 🏻)
EMOJI_SKIN_TONE_LABELS=(Dark Medium-Dark Medium Medium-Light Light)
declare -gA EMOJI_SKIN_TONE_BASES=([👋]=1 [🤚]=1 [🖐]=1 [✋]=1 [🖖]=1 [🫱]=1 [🫲]=1 [🫳]=1 [🫴]=1 [🫷]=1 [🫸]=1 [👌]=1 [🤌]=1 [🤏]=1 [✌]=1 [🤞]=1 [🫰]=1 [🤟]=1 [🤘]=1 [🤙]=1 [👈]=1 [👉]=1 [👆]=1 [🫵]=1 [👇]=1 [☝]=1 [👍]=1 [👎]=1 [✊]=1 [👊]=1 [🤛]=1 [🤜]=1 [👏]=1 [🙌]=1 [🫶]=1 [👐]=1 [🤲]=1 [🙏]=1 [✍]=1 [💅]=1 [🤳]=1 [💪]=1 [🦵]=1 [🦶]=1 [👂]=1 [🦻]=1 [👃]=1 [🧒]=1 [👦]=1 [👧]=1 [🧑]=1 [👱]=1 [👨]=1 [👩]=1 [🧔]=1 [👴]=1 [👵]=1 [🙍]=1 [🙎]=1 [🙅]=1 [🙆]=1 [💁]=1 [🙋]=1 [🧏]=1 [🙇]=1 [🤦]=1 [🤷]=1 [👮]=1 [🕵]=1 [💂]=1 [🥷]=1 [👷]=1 [🫅]=1 [🤴]=1 [👸]=1 [👳]=1 [👲]=1 [🧕]=1 [🤵]=1 [👰]=1 [🤰]=1 [🫄]=1 [🫃]=1 [🤱]=1 [👼]=1 [🎅]=1 [🤶]=1 [🦸]=1 [🦹]=1 [🧙]=1 [🧚]=1 [🧛]=1 [🧜]=1 [🧝]=1 [💆]=1 [💇]=1 [🚶]=1 [🧍]=1 [🧎]=1 [🏃]=1 [💃]=1 [🕺]=1 [🕴]=1 [👯]=1 [🧖]=1 [🧗]=1 [🏇]=1 [🏂]=1 [🏌]=1 [🏄]=1 [🚣]=1 [🏊]=1 [⛹]=1 [🏋]=1 [🚴]=1 [🚵]=1 [🤸]=1 [🤼]=1 [🤽]=1 [🤾]=1 [🤹]=1 [🛀]=1 [🛌]=1 [🧘]=1 [👶]=1 [🖕]=1 [🧓]=1 [🫹]=1 [🫺]=1)
declare -gA EMOJI_SAME_TONE_TEMPLATES=(
  [🤝]=🤝%1
  [👫]=👫%1
  [👬]=👬%1
  [👭]=👭%1
  [💑]=💑%1
  [💏]=💏%1
)
declare -gA EMOJI_TWO_TONE_TEMPLATES=(
  [🤝]=🫱%1‍🫲%2
  [👫]=👩%1‍🤝‍👨%2
  [👬]=👨%1‍🤝‍👨%2
  [👭]=👩%1‍🤝‍👩%2
  [💑]=🧑%1‍❤️‍🧑%2
  [💏]=🧑%1‍❤️‍💋‍🧑%2
  [🧑‍🤝‍🧑]=🧑%1‍🤝‍🧑%2
  [👩‍❤️‍👨]=👩%1‍❤️‍👨%2
  [👩‍❤️‍💋‍👨]=👩%1‍❤️‍💋‍👨%2
  [👨‍❤️‍👨]=👨%1‍❤️‍👨%2
  [👨‍❤️‍💋‍👨]=👨%1‍❤️‍💋‍👨%2
  [👩‍❤️‍👩]=👩%1‍❤️‍👩%2
  [👩‍❤️‍💋‍👩]=👩%1‍❤️‍💋‍👩%2
)

emoji_strip_skin_tones() {
  local emoji_text="$1" tone=""
  for tone in "${EMOJI_SKIN_TONES[@]}"; do
    emoji_text="${emoji_text//"${tone}"/}"
  done
  printf '%s' "${emoji_text}"
}

emoji_with_skin_tone() {
  local -n toned_ref="$1"
  local source_emoji="$2" skin_tone="$3"
  local rest="${source_emoji:1}"

  toned_ref="${source_emoji:0:1}${skin_tone}${rest#"${EMOJI_VARIATION_SELECTOR}"}"
}

emoji_with_two_skin_tones() {
  local -n two_toned_ref="$1"
  local couple_emoji="$2" first_skin_tone="$3" second_skin_tone="$4"
  local template="${EMOJI_TWO_TONE_TEMPLATES[${couple_emoji}]}"

  if [[ "${first_skin_tone}" == "${second_skin_tone}" && -v "EMOJI_SAME_TONE_TEMPLATES[${couple_emoji}]" ]]; then
    template="${EMOJI_SAME_TONE_TEMPLATES[${couple_emoji}]}"
  fi
  template="${template//%1/${first_skin_tone}}"
  two_toned_ref="${template//%2/${second_skin_tone}}"
}

emoji_takes_single_skin_tone() {
  local candidate="$1" position=0

  [[ -v "EMOJI_SKIN_TONE_BASES[${candidate:0:1}]" ]] || return 1
  for ((position = 1; position < ${#candidate}; position++)); do
    [[ -v "EMOJI_SKIN_TONE_BASES[${candidate:position:1}]" ]] && return 1
  done
  return 0
}

emoji_gender_variants_into() {
  local -n variants_ref="$1"
  local emoji_name="$2" db_file="$3"
  local man_name="man ${emoji_name}" woman_name="woman ${emoji_name}" gender="" variant=""

  [[ -n "${emoji_name}" ]] || return 0
  case "${emoji_name}" in
    person | "person "* | "person:"*)
      man_name="man${emoji_name#person}"
      woman_name="woman${emoji_name#person}"
      ;;
  esac
  while IFS=$'\t' read -r gender variant; do
    variants_ref["${gender}"]="${variant}"
  done < <(awk -F '\t' -v man="${man_name}" -v woman="${woman_name}" '
    { name = $2; sub(/^E[0-9.]+ /, "", name) }
    name == man { print "man\t" $1 }
    name == woman { print "woman\t" $1 }
  ' "${db_file}")
}

emoji_choose_row() {
  local -n chosen_index_ref="$1"
  local layout_name="$2" prompt="$3" placeholder="$4"
  shift 4
  local choice="" row_index=0

  choice="$(printf '%s\n' "$@" | emoji_clipboard_dmenu "${prompt}" "${placeholder}" "${layout_name}")" || return 1
  for ((row_index = 0; row_index < $#; row_index++)); do
    [[ "${choice}" == "${@:row_index + 1:1}" ]] || continue
    chosen_index_ref="${row_index}"
    return 0
  done
  return 1
}

emoji_pick_variant() {
  local emoji="$1" description="$2" db_file="$3" layout_name="$4"
  local emoji_name="" first_skin_tone="" preview="" chosen=0 tone_index=0
  local -a rows=() options=()
  local -A gender_variants=()

  [[ "${description}" =~ ^E[0-9.]+\ (.+)$ ]] && emoji_name="${BASH_REMATCH[1]}"
  emoji_gender_variants_into gender_variants "${emoji_name}" "${db_file}"
  if ((${#gender_variants[@]})); then
    options=("${emoji}")
    rows=("${emoji} Person")
    if [[ -n "${gender_variants[man]:-}" ]]; then
      options+=("${gender_variants[man]}")
      rows+=("${gender_variants[man]} Man")
    fi
    if [[ -n "${gender_variants[woman]:-}" ]]; then
      options+=("${gender_variants[woman]}")
      rows+=("${gender_variants[woman]} Woman")
    fi
    emoji_choose_row chosen "${layout_name}" "Gender Variant" "Choose gender variant..." "${rows[@]}" || return 1
    emoji="${options[chosen]}"
  fi

  if [[ -v "EMOJI_TWO_TONE_TEMPLATES[${emoji}]" ]]; then
    rows=("${emoji} Default")
    for tone_index in "${!EMOJI_SKIN_TONES[@]}"; do
      emoji_with_two_skin_tones preview "${emoji}" "${EMOJI_SKIN_TONES[tone_index]}" "${EMOJI_SKIN_TONES[tone_index]}"
      rows+=("${preview} ${EMOJI_SKIN_TONE_LABELS[tone_index]}")
    done
    emoji_choose_row chosen "${layout_name}" "Person 1 Skin Tone" "Choose skin tone for person 1..." "${rows[@]}" || return 1
    if ((chosen > 0)); then
      first_skin_tone="${EMOJI_SKIN_TONES[chosen - 1]}"
      rows=()
      for tone_index in "${!EMOJI_SKIN_TONES[@]}"; do
        emoji_with_two_skin_tones preview "${emoji}" "${first_skin_tone}" "${EMOJI_SKIN_TONES[tone_index]}"
        rows+=("${preview} ${EMOJI_SKIN_TONE_LABELS[tone_index]}")
      done
      emoji_choose_row chosen "${layout_name}" "Person 2 Skin Tone" "Choose skin tone for person 2..." "${rows[@]}" || return 1
      emoji_with_two_skin_tones emoji "${emoji}" "${first_skin_tone}" "${EMOJI_SKIN_TONES[chosen]}"
    fi
  elif emoji_takes_single_skin_tone "${emoji}"; then
    rows=("${emoji} Default")
    for tone_index in "${!EMOJI_SKIN_TONES[@]}"; do
      emoji_with_skin_tone preview "${emoji}" "${EMOJI_SKIN_TONES[tone_index]}"
      rows+=("${preview} ${EMOJI_SKIN_TONE_LABELS[tone_index]}")
    done
    emoji_choose_row chosen "${layout_name}" "Select Skin Tone" "Choose skin tone..." "${rows[@]}" || return 1
    ((chosen == 0)) || emoji_with_skin_tone emoji "${emoji}" "${EMOJI_SKIN_TONES[chosen - 1]}"
  fi

  printf '%s\n' "${emoji}"
}
