default_app_write_user_preferences() {
  local value="$1" preferences_file="${XDG_CONFIG_HOME}/hypr/userprefs.lua" temporary_file
  shift
  if [[ ! -f "${preferences_file}" ]]; then
    mkdir -p "${preferences_file%/*}"
    touch "${preferences_file}"
  fi
  temporary_file="$(mktemp "${preferences_file}.tmp.XXXXXX")"
  awk -v keys="$*" -v value="${value}" -v vars_import='local vars = require("vars")' '
    BEGIN { key_count = split(keys, preference_keys, " ") }
    $0 == vars_import { has_import = 1 }
    {
      for (key_index = 1; key_index <= key_count; key_index++)
        if (index($0, "vars.set(\"" preference_keys[key_index] "\",")) next
      preserved = preserved $0 ORS
    }
    END {
      if (!has_import) print vars_import
      printf "%s", preserved
      for (key_index = 1; key_index <= key_count; key_index++)
        printf "vars.set(\"%s\", \"%s\")\n", preference_keys[key_index], value
    }
  ' "${preferences_file}" >"${temporary_file}"
  chmod --reference="${preferences_file}" "${temporary_file}"
  mv -f "${temporary_file}" "${preferences_file}"
}

default_app_apply() {
  local -n application_ref="$1"
  case "${application_ref[role]}" in
    agent) state_set HYPR_DEFAULT_AGENT "${application_ref[selection]}" env-overrides; return ;;
    browser) env -u BROWSER xdg-settings set default-web-browser "${application_ref[desktop_id]}" ;;
  esac
  local -a preference_keys=("${application_ref[role]^^}")
  local preference_key
  [[ "${application_ref[role]}" != terminal ]] || preference_keys+=(TERMINAL_TUI)
  default_app_write_user_preferences "${application_ref[command]}" "${preference_keys[@]}"
  for preference_key in "${preference_keys[@]}"; do
    state_set "${preference_key}" "${application_ref[command]}" env-overrides
  done
  if [[ "${application_ref[role]}" == terminal ]]; then
    printf '# Terminal emulator preference order\n%s\n' "${application_ref[desktop_id]}" >"${XDG_CONFIG_HOME}/xdg-terminals.list"
  fi
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null
  fi
}
