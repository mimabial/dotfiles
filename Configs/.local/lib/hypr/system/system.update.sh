#!/usr/bin/env bash

[[ -f /etc/arch-release ]] || exit 0

# shellcheck disable=SC1091
source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"
if aur_helper="$(get_aur_helper)"; then
  :
else
  aur_helper=""
fi
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
temp_file="${runtime_dir}/update_info"

normalize_count() {
  [[ "${1:-0}" =~ ^[0-9]+$ ]] && printf '%s\n' "${1:-0}" || printf '0\n'
}

count_updates() {
  [[ -n "${1-}" ]] && grep -c '^' <<<"${1-}" || echo 0
}

read_update_info() {
  official=0
  aur=0
  flatpak=0

  [[ -f "$temp_file" ]] || return 1

  while IFS="=" read -r key value; do
    case "$key" in
      OFFICIAL_UPDATES) official="$value" ;;
      AUR_UPDATES) aur="$value" ;;
      FLATPAK_UPDATES) flatpak="$value" ;;
    esac
  done <"$temp_file"

  official="$(normalize_count "$official")"
  aur="$(normalize_count "$aur")"
  flatpak="$(normalize_count "$flatpak")"
}

write_update_info() {
  mkdir -p "$runtime_dir"
  cat >"$temp_file" <<EOF
OFFICIAL_UPDATES=$1
AUR_UPDATES=$2
FLATPAK_UPDATES=$3
EOF
}

require_update_info() {
  [[ -f "$temp_file" ]] && return 0
  echo "No upgrade info found. Please run the script without parameters first."
  return 1
}

run_updates() {
  trap 'pkill -RTMIN+20 waybar' EXIT
  require_update_info || return 1
  read_update_info || return 1
  command -v fastfetch >/dev/null 2>&1 && fastfetch
  printf '[Official] %-10s\n[AUR]      %-10s\n[Flatpak]  %-10s\n' "$official" "$aur" "$flatpak"
  [[ -n "${aur_helper}" ]] && "$aur_helper" -Syu
  pkg_installed flatpak && flatpak update
}

if [[ "${1:-}" == "up" ]]; then
  require_update_info || exit 1
  exec hyprshell launch/terminal-present.sh --hypr-profile dialog --app-id "org.tui.SystemUpdate" --title "System Update" -- hyprshell system/system.update.sh --run-upgrade
fi

if [[ "${1:-}" == "--run-upgrade" ]]; then
  run_updates
  exit $?
fi

temp_db=$(mktemp -d "${XDG_RUNTIME_DIR:-"/tmp"}/checkupdates_db_XXXXXX")
trap '[ -n "$temp_db" ] && rm -rf "$temp_db" 2>/dev/null' EXIT INT TERM

ofc_list=$(CHECKUPDATES_DB="$temp_db" checkupdates 2>/dev/null)
ofc=$(count_updates "$ofc_list")

if [[ -n "${aur_helper}" ]]; then
  aur_list=$("${aur_helper}" -Qua 2>/dev/null)
  aur=$(count_updates "$aur_list")
else
  aur_list=""
  aur=0
fi

if pkg_installed flatpak; then
  fpk_list=$(flatpak remote-ls --updates --columns=application,version,branch 2>/dev/null)
  fpk=$(count_updates "$fpk_list")
else
  fpk=0
  fpk_list=""
fi

upd=$((ofc + aur + fpk))

format_package_updates() {
  local update_list="${1-}"
  local line=""
  local pkg=""
  local old_ver=""
  local new_ver=""
  local body=""

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    read -r pkg old_ver _arrow new_ver <<<"$line"
    body+="  ${pkg}  ${old_ver} → ${new_ver}\n"
  done <<<"$update_list"
  printf '%s' "$body"
}

format_flatpak_updates() {
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
    body+="  ${pkg_name}  ${old_ver} → ${new_ver}\n"
  done <<<"$fpk_list"
  printf '%s' "$body"
}

append_tooltip_section() {
  local header="$1"
  local body="$2"
  [[ -n "$body" ]] || return 0
  [[ -n "$content" ]] && content+=$'\n'
  content+="<b>${header}:</b>\n${body}"
}

build_tooltip() {
  local aur_label="${aur_helper^^}"
  local title=""
  content=""
  aur_label="${aur_label:-NONE}"
  title="<b>${upd} Updates</b>\n  ${ofc} Official (Pacman)\n  ${aur} AUR (${aur_label})\n  ${fpk} Universal (Flatpak)"

  append_tooltip_section "PACMAN" "$(format_package_updates "$ofc_list")"
  append_tooltip_section "AUR" "$(format_package_updates "$aur_list")"
  append_tooltip_section "FLATPAK" "$(format_flatpak_updates)"

  printf '%s' "${title}"
  [[ -n "$content" ]] && printf '\n\n%s' "$content"
}

print_waybar_json() {
  local text="$1"
  local tooltip="$2"
  jq -cn --arg text "$text" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip}'
}

write_update_info "$ofc" "$aur" "$fpk"
if [ "$upd" -eq 0 ]; then
  print_waybar_json "" " Packages are up to date"
else
  print_waybar_json "󰮯" "$(build_tooltip)"
fi
