keyboard_validate_settings_shape() {
  jq -e '
    (.layouts | type == "array" and length > 0)
    and all(.layouts[];
      (.layout | type == "string" and test("^[A-Za-z0-9_+-]+$"))
      and (.variant | type == "string" and test("^[A-Za-z0-9_+-]*$")))
    and ([.layouts[] | [.layout, .variant]] | unique | length) == (.layouts | length)
    and (.switchOption | type == "string" and test("^(|grp:[A-Za-z0-9_+-]+)$"))
    and (.nonGroupOptions | type == "array")
    and all(.nonGroupOptions[];
      type == "string" and test("^[A-Za-z0-9_:+-]+$") and (startswith("grp:") | not))
  ' >/dev/null 2>&1 <<<"$1"
}

keyboard_compile_layout() {
  xkbcli compile-keymap \
    --layout "$(keyboard_layout_csv "$1")" \
    --variant "$(keyboard_variant_csv "$1")" \
    --options "$(keyboard_options_csv "$1")" >/dev/null 2>&1
}

keyboard_layout_has_latin_letters() {
  local layout="$1" variant="${2:-}" letters=""
  local -a command=(xkbcli compile-keymap --layout "${layout}")
  [[ -z "${variant}" ]] || command+=(--variant "${variant}")
  letters=$("${command[@]}" 2>/dev/null \
    | sed -nE 's/.*\{[[:space:]]*\[[[:space:]]*([a-z])[[:space:]]*,.*/\1/p' \
    | sort -u | tr -d '\n')
  [[ ${#letters} -eq 26 ]]
}

keyboard_validate_candidate() {
  local layout_settings="$1" catalog="" option="" shortcut="" first_layout="" first_variant=""
  keyboard_validate_settings_shape "${layout_settings}" || keyboard_error 'Invalid keyboard-layout state; nothing was changed.'
  shortcut=$(jq -r '.switchOption' <<<"${layout_settings}")
  if [[ -n "${shortcut}" ]] \
    && { [[ "${shortcut}" =~ _switch(_|$) ]] \
      || [[ "${shortcut}" != grp:toggle && ! "${shortcut}" =~ _toggle(_|$) && ! "${shortcut}" =~ _select$ ]]; }; then
    keyboard_error 'Choose a supported XKB layout-switching shortcut; nothing was changed.'
  fi

  catalog=$(xkbcli list --load-exotic 2>/dev/null) \
    || keyboard_error 'The installed XKB catalog could not be read; nothing was changed.'
  while IFS= read -r option; do
    [[ -z "${option}" ]] && continue
    grep -Fqx "  - name: '${option}'" <<<"${catalog}" \
      || keyboard_error "XKB does not provide option '${option}'; nothing was changed."
  done < <(jq -r '.nonGroupOptions[], .switchOption' <<<"${layout_settings}")
  keyboard_compile_layout "${layout_settings}" || keyboard_error 'XKB rejected that layout, variant, or shortcut; nothing was changed.'

  first_layout=$(jq -r '.layouts[0].layout' <<<"${layout_settings}")
  first_variant=$(jq -r '.layouts[0].variant' <<<"${layout_settings}")
  keyboard_layout_has_latin_letters "${first_layout}" "${first_variant}" \
    || keyboard_error 'Keep a Latin layout first so letter keybindings remain usable.'
}
