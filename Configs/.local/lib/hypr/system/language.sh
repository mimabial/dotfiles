#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

usage="Usage: hyprshell system/language install|remove|system|display [LOCALE]
Without LOCALE, list the locales the action accepts.
  install  generate LOCALE and install its spell-check dictionaries
  remove   drop LOCALE and the dictionaries no remaining locale uses
  system   make LOCALE the system language (applies at next login)
  display  make LOCALE your account's language; the system language clears it
  current [display]  print the system language, or your account's"
hypr_help_guard "${usage}" "$@"

locale_gen=/etc/locale.gen
locale_conf=/etc/locale.conf
display_conf="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env.d/02-language.sh"

utf8_locales() { sed -nE "s/^$1([^#[:space:]]+) UTF-8[[:space:]]*\$/\1/p" "${locale_gen}"; }
system_locale() { sed -n 's/^LANG=//p' "${locale_conf}"; }
display_locale() { if [[ -f "${display_conf}" ]]; then sed -n 's/^export LANG=//p' "${display_conf}"; else system_locale; fi; }

labelled() {
  local -a locales=()
  mapfile -t locales
  ((${#locales[@]})) || return 0
  cd /usr/share/i18n/locales
  awk -F'"' -v locales="${locales[*]}" 'BEGIN { split(locales, locale, " ") }
    /^language/ { language = $2 }
    /^territory/ { print language ($2 ? " (" $2 ")" : "") " — " locale[ARGIND]; nextfile }' "${locales[@]/.UTF-8}"
}

dictionaries() {
  local query="$1" locale="" codes=()
  shift
  for locale; do
    locale="${locale%%[.@]*}"
    codes+=("${locale%%_*}" "${locale,,}")
  done
  local IFS='|'
  pacman "${query}" | grep -E "^(hunspell|aspell|hyphen|mythes)-(${codes[*]})(-|\$)"
}

toggle_locale() {
  sudo sed -Ei "s/^$1(${locale} )/$2\1/" "${locale_gen}"
  sudo locale-gen
}

action="${1:-}"
locale="${2:-}"

case "${action}:${locale}" in
  install:) utf8_locales '#' | labelled ;;
  remove:) utf8_locales '' | grep -vxF "$(system_locale)" | labelled ;;
  system: | display:) utf8_locales '' | labelled ;;
  current:display) display_locale | labelled ;;
  current:*) system_locale | labelled ;;
  install:*)
    toggle_locale '#' ''
    mapfile -t packages < <(dictionaries -Slq "${locale}" | awk -F- '!seen[$1]++')
    ((${#packages[@]} == 0)) || hyprshell pm add "${packages[@]}"
    ;;
  remove:*)
    toggle_locale '' '#'
    mapfile -t remaining < <(utf8_locales '')
    mapfile -t packages < <(dictionaries -Qq "${locale}" | grep -vxFf <(dictionaries -Qq "${remaining[@]}"))
    ((${#packages[@]} == 0)) || hyprshell pm --noconfirm remove "${packages[@]}"
    ;;
  system:*)
    pkexec sed -i -e "\$a LANG=${locale}" -e '/^LANG=/d' "${locale_conf}"
    printf 'System language is now %s; it applies at next login.\n' "${locale}"
    ;;
  display:*)
    if [[ "${locale}" == "$(system_locale)" ]]; then rm -f "${display_conf}"; else printf 'export LANG=%s\n' "${locale}" >"${display_conf}"; fi
    printf 'Display language is now %s; it applies at next login.\n' "${locale}"
    ;;
  *) printf '%s\n' "${usage}" >&2; exit 2 ;;
esac
