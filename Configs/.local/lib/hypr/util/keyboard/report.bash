keyboard_emit_status() {
  local layout_settings="${1:-}" index="" count="" keymap="" code="" layouts="" tooltip=""
  [[ -n "${layout_settings}" ]] || layout_settings=$(keyboard_current_settings)
  index=$(keyboard_active_layout_index)
  count=$(jq '.layouts | length' <<<"${layout_settings}")
  (( index < count )) || index=0
  keymap=$(keyboard_device_field active_keymap 2>/dev/null || true)
  code=$(jq -r --argjson index "${index}" '.layouts[$index].layout // ""' <<<"${layout_settings}")
  layouts=$(keyboard_layout_csv "${layout_settings}")
  tooltip=${keymap:-Unknown layout}
  [[ -z "${layouts}" ]] || tooltip+=$'\n'"${layouts}"

  jq -c \
    --arg text "${code}" \
    --arg alt "${keymap}" \
    --arg layouts "${layouts}" \
    --arg variants "$(keyboard_variant_csv "${layout_settings}")" \
    --arg options "$(keyboard_options_csv "${layout_settings}")" \
    --arg tooltip "${tooltip}" \
    --argjson activeIndex "${index}" '
      . + {
        text: $text,
        alt: $alt,
        configured: .layouts,
        layouts: $layouts,
        variants: $variants,
        options: $options,
        tooltip: $tooltip,
        activeIndex: $activeIndex
      }
    ' <<<"${layout_settings}"
}
