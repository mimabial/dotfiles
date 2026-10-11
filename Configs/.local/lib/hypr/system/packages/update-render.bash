updates_format_package_lines() {
  local update_list="${1-}"
  local line=""
  local pkg=""
  local old_ver=""
  local new_ver=""
  local body=""

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    read -r pkg old_ver _arrow new_ver <<<"$line"
    body+="  ${pkg}  ${old_ver} → ${new_ver}"$'\n'
  done <<<"$update_list"
  printf '%s' "$body"
}

updates_format_flatpak_lines() {
  local line=""
  local app=""
  local new_ver=""
  local branch=""
  local old_ver=""
  local pkg_name=""
  local body=""

  while IFS=$'\t' read -r app new_ver branch; do
    [[ -n "$app" ]] || continue
    old_ver=$(flatpak info "$app" 2>/dev/null | awk '/Version:/ {print $2; exit}')
    old_ver="${old_ver:-installed}"
    pkg_name="${app##*.}"
    body+="  ${pkg_name}  ${old_ver} → ${new_ver}"$'\n'
  done <<<"$flatpak_update_lines"
  printf '%s' "$body"
}

updates_format_errors() {
  [[ "${#system_update_errors[@]}" -gt 0 ]] || return 0
  printf '  %s\n' "${system_update_errors[@]}"
}

updates_escape_pango() { sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }

updates_append_tooltip_section() {
  local header="$1"
  local body
  body="$(updates_escape_pango <<<"$2")"
  [[ -n "$body" ]] || return 0
  [[ -n "$content" ]] && content+=$'\n'
  content+="<b>${header}:</b>"$'\n'"${body}"
}

updates_build_tooltip() {
  local aur_label="${update_aur_helper^^}"
  local title=""
  content=""
  aur_label="${aur_label:-NONE}"
  title="<b>${total_update_count} Updates</b>"$'\n'"  ${repo_update_count} Official (Pacman)"$'\n'"  ${aur_update_count} AUR (${aur_label})"$'\n'"  ${flatpak_update_count} Universal (Flatpak)"

  updates_append_tooltip_section "PACMAN" "$(updates_format_package_lines "$repo_update_lines")"
  updates_append_tooltip_section "AUR" "$(updates_format_package_lines "$aur_update_lines")"
  updates_append_tooltip_section "FLATPAK" "${flatpak_updates-}"
  updates_append_tooltip_section "CHECK ERRORS" "$(updates_format_errors)"

  printf '%s' "${title}"
  [[ -n "$content" ]] && printf '\n\n%s' "$content"
}

updates_package_rows_json() {
  # "pkg old -> new [age]" lines (pacman/aur) into objects the popup can render
  jq -R -s -c 'split("\n")
    | map(select(length > 0)
      | (split(" ") | map(select(length > 0)))
      | select(length > 0)
      | (index("->") // index("\u2192")) as $arrow
      | {name: .[0],
         from: (.[1] // ""),
         to: (if $arrow then (.[$arrow + 1] // "") else (.[-1] // "") end)})' <<<"${1-}"
}

updates_flatpak_rows_json() {
  jq -R -s -c 'split("\n")
    | map(select(length > 0)
      | sub("^ +"; "")
      | (split("  ") | map(select(length > 0)))
      | select(length > 0)
      | {name: .[0], from: ((.[1] // "") | split(" \u2192 ") | .[0] // ""),
         to: ((.[1] // "") | split(" \u2192 ") | .[1] // "")})' <<<"${flatpak_updates-}"
}

updates_errors_json() {
  local list=""
  ((${#system_update_errors[@]})) && printf -v list '%s\n' "${system_update_errors[@]}"
  jq -R -s -c 'split("\n") | map(select(length > 0))' <<<"${list}"
}

updates_system_facts_json() {
  local upgraded=""
  upgraded="$(updates_last_upgrade_epoch)"
  jq -cn --argjson checked "${EPOCHSECONDS}" \
    --argjson installed "$(pacman -Qq 2>/dev/null | wc -l)" \
    --argjson upgraded "${upgraded}" \
    '{checked: $checked, installed: $installed, upgraded: $upgraded}'
}

updates_write_bar_report() {
  local text="$1"
  local tooltip="$2"
  local class="${3:-}"
  local payload
  payload="$(jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    --argjson pacman "$(updates_package_rows_json "${repo_update_lines-}")" \
    --argjson aur "$(updates_package_rows_json "${aur_update_lines-}")" \
    --argjson flatpak "$(updates_flatpak_rows_json)" \
    --argjson errors "$(updates_errors_json)" \
    --argjson system "$(updates_system_facts_json)" \
    '{text:$text, tooltip:$tooltip, class:$class,
      packages: {pacman: $pacman, aur: $aur, flatpak: $flatpak}, errors: $errors, system: $system}')"
  mkdir -p "${update_runtime_dir}"
  local tmp
  tmp="$(mktemp "${update_cache_path}.XXXXXX")"
  if ! printf '%s\n' "${payload}" >"${tmp}" || ! mv -f "${tmp}" "${update_cache_path}"; then
    rm -f "${tmp}"
  fi
  printf '%s\n' "${payload}"
}

