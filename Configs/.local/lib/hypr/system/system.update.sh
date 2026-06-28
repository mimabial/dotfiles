#!/usr/bin/env bash

set -euo pipefail

[[ -f /etc/arch-release ]] || exit 0

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash"
hypr_runtime_require system || exit 1

hypr_help_guard "Usage: hyprshell system/system.update [up|--run-upgrade]
Report pending updates as waybar JSON; 'up' opens an upgrade terminal." "$@"

if aur_helper="$(get_aur_helper)"; then
  :
else
  aur_helper=""
fi
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
temp_file="${runtime_dir}/update_info"
temp_db=""
declare -a system_update_errors=()

system_update_refresh_waybar() {
  local exit_code="${1:-$?}"
  pkill -RTMIN+20 waybar >/dev/null 2>&1 || true
  return "${exit_code}"
}

system_update_cleanup_temp_db() {
  local exit_code="${1:-$?}"
  if [[ -n "${temp_db}" ]]; then
    rm -rf "${temp_db}" 2>/dev/null || true
    temp_db=""
  fi
  return "${exit_code}"
}

system_update_handle_signal() {
  local signal_exit_code="$1"
  system_update_cleanup_temp_db "${signal_exit_code}"
  exit "${signal_exit_code}"
}

normalize_count() {
  [[ "${1:-0}" =~ ^[0-9]+$ ]] && printf '%s\n' "${1:-0}" || printf '0\n'
}

count_updates() {
  awk 'NF {count++} END {print count + 0}' <<<"${1-}"
}

capture_update_list() {
  local out_var="$1"
  local label="$2"
  shift 2

  local output=""
  local stderr_file=""
  local stderr_output=""
  local rc=0

  stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/system-update-${label}.XXXXXX")" || return 1
  set +e
  output="$("$@" 2>"${stderr_file}")"
  rc=$?
  set -e
  stderr_output="$(<"${stderr_file}")"
  rm -f "${stderr_file}"

  printf -v "${out_var}" '%s' "${output}"

  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi

  if [[ -n "${output}" && -z "${stderr_output}" ]]; then
    return 0
  fi

  case "${rc}" in
    1 | 2)
      [[ -z "${stderr_output}" ]] && return 0
      ;;
  esac

  system_update_errors+=("${label}: ${stderr_output:-exit ${rc}}")
  [[ -n "${output}" ]] && return 0
  return 0
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
  trap 'system_update_refresh_waybar "$?"' EXIT
  require_update_info || return 1
  read_update_info || return 1
  command -v fastfetch >/dev/null 2>&1 && fastfetch
  printf '[Official] %-10s\n[AUR]      %-10s\n[Flatpak]  %-10s\n' "$official" "$aur" "$flatpak"
  if [[ -n "${aur_helper}" ]]; then
    "$aur_helper" -Syu
  else
    sudo pacman -Syu
  fi
  if pkg_installed flatpak; then
    flatpak update
  fi
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
trap 'system_update_cleanup_temp_db "$?"' EXIT
trap 'system_update_handle_signal 130' INT
trap 'system_update_handle_signal 143' TERM

capture_update_list ofc_list pacman env CHECKUPDATES_DB="$temp_db" checkupdates
ofc=$(count_updates "$ofc_list")

if [[ -n "${aur_helper}" ]]; then
  capture_update_list aur_list aur "${aur_helper}" -Qua
  aur=$(count_updates "$aur_list")
else
  aur_list=""
  aur=0
fi

if pkg_installed flatpak; then
  capture_update_list fpk_list flatpak flatpak remote-ls --updates --columns=application,version,branch
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
    body+="  ${pkg}  ${old_ver} → ${new_ver}"$'\n'
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
    body+="  ${pkg_name}  ${old_ver} → ${new_ver}"$'\n'
  done <<<"$fpk_list"
  printf '%s' "$body"
}

format_check_errors() {
  [[ "${#system_update_errors[@]}" -gt 0 ]] || return 0
  printf '  %s\n' "${system_update_errors[@]}"
}

append_tooltip_section() {
  local header="$1"
  local body="$2"
  [[ -n "$body" ]] || return 0
  [[ -n "$content" ]] && content+=$'\n'
  content+="<b>${header}:</b>"$'\n'"${body}"
}

build_tooltip() {
  local aur_label="${aur_helper^^}"
  local title=""
  content=""
  aur_label="${aur_label:-NONE}"
  title="<b>${upd} Updates</b>"$'\n'"  ${ofc} Official (Pacman)"$'\n'"  ${aur} AUR (${aur_label})"$'\n'"  ${fpk} Universal (Flatpak)"

  append_tooltip_section "PACMAN" "$(format_package_updates "$ofc_list")"
  append_tooltip_section "AUR" "$(format_package_updates "$aur_list")"
  append_tooltip_section "FLATPAK" "$(format_flatpak_updates)"
  append_tooltip_section "CHECK ERRORS" "$(format_check_errors)"

  printf '%s' "${title}"
  [[ -n "$content" ]] && printf '\n\n%s' "$content"
}

print_waybar_json() {
  local text="$1"
  local tooltip="$2"
  local class="${3:-}"
  jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" '{text:$text, tooltip:$tooltip, class:$class}'
}

write_update_info "$ofc" "$aur" "$fpk"
if [[ "${#system_update_errors[@]}" -gt 0 && "$upd" -eq 0 ]]; then
  print_waybar_json "󰅚" "$(build_tooltip)" "error"
elif [[ "${#system_update_errors[@]}" -gt 0 ]]; then
  print_waybar_json "󰮯" "$(build_tooltip)" "warning"
elif [ "$upd" -eq 0 ]; then
  print_waybar_json "" " Packages are up to date" "up-to-date"
else
  print_waybar_json "󰮯" "$(build_tooltip)" "updates"
fi
