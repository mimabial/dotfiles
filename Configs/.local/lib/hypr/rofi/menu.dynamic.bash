#!/usr/bin/env bash

nerd_font_display_name_from_package() {
  local pkg="$1"
  local display=""

  display="$(printf '%s\n' "${pkg}" | sed -E 's/^(ttf-|otf-)//; s/-(nerd|nerdfonts)$//' | sed 's/-/ /g')"
  display="$(printf '%s\n' "${display}" | awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i,1,1)) substr($i,2); print}')"
  [[ -n "${display}" ]] || display="${pkg}"
  printf '%s\n' "${display}"
}

nerd_font_metadata_display_name() {
  local description="$1"

  if [[ "${description}" =~ ^Patched[[:space:]]font[[:space:]](.+)[[:space:]]from[[:space:]]nerd[[:space:]]fonts[[:space:]]library$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

nerd_font_populate_metadata_labels() {
  local out_map_name="$1"
  shift
  local -a packages=("$@")
  local pkg=""
  local description=""
  local label=""

  local -n out_map_ref="${out_map_name}"

  [[ "${#packages[@]}" -gt 0 ]] || return 0

  while IFS=$'\t' read -r pkg description; do
    [[ -n "${pkg}" ]] || continue
    label="$(nerd_font_metadata_display_name "${description}" || true)"
    [[ -n "${label}" ]] || continue
    out_map_ref["${pkg}"]="${label}"
  done < <(
    pacman -Si -- "${packages[@]}" 2>/dev/null |
      awk '
        /^Name[[:space:]]*:/ {
          sub(/^[^:]+:[[:space:]]*/, "", $0)
          name=$0
          next
        }
        /^Description[[:space:]]*:/ {
          sub(/^[^:]+:[[:space:]]*/, "", $0)
          if (name != "") printf "%s\t%s\n", name, $0
          name=""
        }
      '
  )
}

nerd_font_menu_build() {
  local mode="$1"
  local out_labels_name="$2"
  local out_map_name="$3"
  local package_list=""
  local pkg=""
  local label=""
  local -a packages=()
  local -A seen_labels=()
  local -A metadata_labels=()

  local -n out_labels_ref="${out_labels_name}"
  local -n out_map_ref="${out_map_name}"
  out_labels_ref=()
  out_map_ref=()

  case "${mode}" in
    installable)
      package_list="$(hyprshell fonts/font-nerd-install.sh --list-installable 2>/dev/null || true)"
      ;;
    installed)
      package_list="$(hyprshell fonts/font-nerd-remove.sh --list-installed 2>/dev/null || true)"
      ;;
    unused)
      package_list="$(hyprshell fonts/font-nerd-remove.sh --list-unused 2>/dev/null || true)"
      ;;
    *)
      return 1
      ;;
  esac

  mapfile -t packages < <(printf '%s\n' "${package_list}" | sed '/^$/d')
  nerd_font_populate_metadata_labels metadata_labels "${packages[@]}"

  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    label="${metadata_labels["${pkg}"]:-}"
    [[ -n "${label}" ]] || label="$(nerd_font_display_name_from_package "${pkg}")"
    if [[ -n "${seen_labels["${label}"]:-}" ]]; then
      label="${label} [${pkg}]"
    fi
    seen_labels["${label}"]=1
    out_labels_ref+=("${label}")
    out_map_ref["${label}"]="${pkg}"
  done <<<"${package_list}"
}

show_font_menu() {
  local font_list=""
  local font=""
  local vars_file=""
  local stock="JetBrainsMono Nerd Font"

  font_list="$(hyprshell fonts/font-list.sh)"
  font="$(menu "Select Font" "Theme Default\n${font_list}")"

  if [[ -z "${font}" || "${font}" == "CNCLD" ]]; then
    menu_exit_or_show style
    return 0
  fi

  if [[ "${font}" == "Theme Default" ]]; then
    vars_file="${HYPR_DATA_HOME:-$HOME/.local/share/hypr}/variables.conf"
    rm -f "${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/userfonts.conf"
    if [[ -f "${vars_file}" ]]; then
      sed -i "s|^\\\$MONOSPACE_FONT=.*|\$MONOSPACE_FONT=${stock}|;s|^\\\$BAR_FONT=.*|\$BAR_FONT=${stock}|;s|^\\\$MENU_FONT=.*|\$MENU_FONT=${stock}|" "${vars_file}"
    fi
    hyprctl reload >/dev/null 2>&1
    hyprshell fonts/font-sync.sh >/dev/null 2>&1 || true
    hyprshell service/restart-waybar.sh >/dev/null 2>&1 || true
  else
    hyprshell fonts/font-set.sh "${font}" >/dev/null 2>&1 &
  fi
}

show_setup_power_profile_menu() {
  local profile=""

  profile="$(menu "Power Profile" "$(hyprshell system/powerprofiles.sh)" "$(powerprofilesctl get)")"
  if [[ -z "${profile}" || "${profile}" == "CNCLD" ]]; then
    menu_exit_or_show setup
    return 0
  fi

  powerprofilesctl set "${profile}"
}

show_install_font_menu() {
  local selection=""
  local package=""
  local -a font_labels=()
  local -A font_packages=()

  nerd_font_menu_build installable font_labels font_packages
  if [[ "${#font_labels[@]}" -gt 0 ]]; then
    selection="$(menu "Install Font" "$(printf '%s\n' "${font_labels[@]}")")"
  else
    selection="$(menu "Install Font" "No installable Nerd Fonts")"
  fi

  case "${selection}" in
    "No installable Nerd Fonts" | "" | "CNCLD")
      menu_exit_or_show install
      ;;
    *)
      package="${font_packages["${selection}"]:-}"
      [[ -n "${package}" ]] || {
        show_install_font_menu
        return 0
      }
      present_terminal --hypr-profile dialog --app-id org.font.Install --title "Install ${selection}" -- hyprshell fonts/font-nerd-install.sh --packages "${package}"
      ;;
  esac
}

show_remove_font_menu() {
  local mode="${1:-all}"
  local unused_option="  Unused"
  local prompt="Remove Font"
  local empty_label="No installed Nerd Fonts"
  local selection=""
  local package=""
  local -a font_labels=()
  local -A font_packages=()

  case "${mode}" in
    unused)
      prompt="Remove Unused Font"
      empty_label="No unused Nerd Fonts"
      nerd_font_menu_build unused font_labels font_packages
      ;;
    *)
      nerd_font_menu_build installed font_labels font_packages
      ;;
  esac

  if [[ "${#font_labels[@]}" -gt 0 ]]; then
    if [[ "${mode}" == "unused" ]]; then
      selection="$(menu "${prompt}" "$(printf '%s\n' "${font_labels[@]}")")"
    else
      selection="$(menu "${prompt}" "${unused_option}\n$(printf '%s\n' "${font_labels[@]}")")"
    fi
  else
    if [[ "${mode}" == "unused" ]]; then
      selection="$(menu "${prompt}" "${empty_label}")"
    else
      selection="$(menu "${prompt}" "${unused_option}\n${empty_label}" "${unused_option}")"
    fi
  fi

  case "${selection}" in
    "${unused_option}")
      show_remove_font_menu unused
      ;;
    "${empty_label}" | "" | "CNCLD")
      menu_exit_or_show remove
      ;;
    *)
      package="${font_packages["${selection}"]:-}"
      [[ -n "${package}" ]] || {
        show_remove_font_menu
        return 0
      }
      present_terminal --hypr-profile dialog --app-id org.font.Remove --title "Remove ${selection}" -- hyprshell fonts/font-nerd-remove.sh --packages "${package}"
      ;;
  esac
}

show_search_all_menu() {
  local selection=""
  local action_id=""
  local options=""
  local width_override=""
  local -a search_labels=()
  local -A search_actions=()

  menu_collect_search_entries main search_labels search_actions
  options="$(printf '%s\n' "${search_labels[@]}")"
  width_override="$(
    rofi_theme_width_multiplier_override menutree "${ROFI_MENU_SEARCH_WIDTH_MULTIPLIER:-2.2}" 650px 2>/dev/null || true
  )"
  selection="$(menu "Search All" "${options}" "" "${width_override}")"

  if [[ -z "${selection}" || "${selection}" == "CNCLD" ]]; then
    menu_exit_or_show main
    return 0
  fi

  action_id="${search_actions["${selection}"]:-}"
  [[ -n "${action_id}" ]] && menu_run_action "${action_id}"
}

menu_run_action_dynamic() {
  local action_id="$1"

  case "${action_id}" in
    search_all)
      show_search_all_menu
      return 0
      ;;
    style_font)
      show_font_menu
      ;;
    setup_power_profile)
      show_setup_power_profile_menu
      ;;
    install_font)
      show_install_font_menu
      ;;
    remove_font)
      show_remove_font_menu
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_dynamic
