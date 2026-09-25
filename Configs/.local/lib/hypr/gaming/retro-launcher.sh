#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_runtime_require rofi
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

usage() {
  printf 'Usage: hyprshell gaming/retro-launcher.sh [--remove | CORE ROM]\n'
}

pick() {
  local prompt="$1"
  local options="$2"
  local -a rofi_args=()

  rofi_build_standard_menu_args rofi_args "${prompt}" "${prompt}" "$(rofi_resolve_theme clipboard)"
  printf '%s\n' "${options}" | rofi_with_background_theme "${rofi_args[@]}" -no-custom -no-show-icons
}

remove_launcher() {
  local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  local file=""
  local name=""
  local option=""
  local selection=""
  local -a files=()
  local -a options=()

  while IFS= read -r -d '' file; do
    grep -Eq '^X-Hypr-RetroArch=true$|^Exec=retroarch[[:space:]].*-L[[:space:]]' "${file}" || continue
    name="$(sed -n 's/^Name=//p' "${file}" | head -n 1)"
    files+=("${file}")
    options+=("${name:-${file##*/}} — ${file##*/}")
  done < <(find "${desktop_dir}" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)

  ((${#files[@]})) || { dunstify -i dialog-information 'RetroArch launchers' 'No game launchers found'; return 0; }
  selection="$(pick 'Remove RetroArch launcher' "$(printf '%s\n' "${options[@]}")")" || return 0
  for option in "${!options[@]}"; do
    [[ "${options[${option}]}" == "${selection}" ]] || continue
    if command -v gio >/dev/null 2>&1; then
      gio trash "${files[${option}]}"
    else
      rm -f -- "${files[${option}]}"
    fi
    update-desktop-database "${desktop_dir}" >/dev/null 2>&1 || true
    dunstify -i user-trash 'RetroArch launcher removed' "${selection%% — *}"
    return 0
  done
}

desktop_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\`/\\\`}"
  value="${value//\$/\\\$}"
  printf '"%s"' "${value}"
}

case "${1:-}" in
  --remove) remove_launcher; exit ;;
  -h | --help) usage; exit 0 ;;
esac

if (($# == 0)); then
  core_dir=/usr/lib/libretro
  rom_dir="${HOME}/Games/roms"
  mapfile -t cores < <(find "${core_dir}" -maxdepth 1 -type f -name '*_libretro.so' -printf '%f\n' 2>/dev/null | sed 's/_libretro\.so$//' | sort)
  ((${#cores[@]})) || { dunstify -u critical -i dialog-error 'No RetroArch cores found' "${core_dir}"; exit 1; }
  core="$(pick 'RetroArch core' "$(printf '%s\n' "${cores[@]}")")" || exit 0
  mapfile -t roms < <(find "${rom_dir}" -type f \
    \( -iname '*.7z' -o -iname '*.bin' -o -iname '*.chd' -o -iname '*.cue' -o -iname '*.gb' -o -iname '*.gba' -o -iname '*.gbc' -o -iname '*.iso' -o -iname '*.m3u' -o -iname '*.md' -o -iname '*.n64' -o -iname '*.nds' -o -iname '*.nes' -o -iname '*.pbp' -o -iname '*.sfc' -o -iname '*.smc' -o -iname '*.zip' -o -iname '*.z64' \) \
    -printf '%P\n' 2>/dev/null | sort)
  ((${#roms[@]})) || { dunstify -u critical -i dialog-error 'No ROMs found' "Put ROMs in ${rom_dir}"; exit 1; }
  rom="$(pick 'Retro game' "$(printf '%s\n' "${roms[@]}")")" || exit 0
  game_path="${rom_dir}/${rom}"
elif (($# == 2)); then
  core="$1"
  game_path="$2"
else
  usage >&2
  exit 2
fi

[[ "${core}" == */* ]] && core_path="${core}" || core_path="/usr/lib/libretro/${core}_libretro.so"
[[ -f "${core_path}" ]] || { printf 'Core not found: %s\n' "${core_path}" >&2; exit 1; }
[[ -f "${game_path}" ]] || { printf 'Game not found: %s\n' "${game_path}" >&2; exit 1; }

game_name="$(basename "${game_path}")"
game_name="${game_name%.*}"
game_name="$(sed -E 's/[[:space:]]*\([^)]*\)//g; s/[[:space:]]+/ /g; s/^ | $//g' <<<"${game_name}")"
desktop_id="$(tr '[:upper:]' '[:lower:]' <<<"${game_name}" | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//')"
desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
desktop_file="${desktop_dir}/${desktop_id}.desktop"
temp_file=""
mkdir -p "${desktop_dir}"
temp_file="$(mktemp "${desktop_file}.tmp.XXXXXX")"
{
  printf '[Desktop Entry]\nVersion=1.0\nName=%s\n' "${game_name}"
  printf 'Comment=Play %s with RetroArch\n' "${game_name}"
  printf 'Exec=retroarch -L %s %s\n' "$(desktop_quote "${core_path}")" "$(desktop_quote "${game_path}")"
  printf 'Terminal=false\nType=Application\nIcon=retro-gaming\nStartupNotify=true\nCategories=Game;Emulator;\nX-Hypr-RetroArch=true\n'
} >"${temp_file}"
chmod 755 "${temp_file}"
mv -f "${temp_file}" "${desktop_file}"
update-desktop-database "${desktop_dir}" >/dev/null 2>&1 || true
dunstify -i retro-gaming "${game_name} installed" 'Open it from the app launcher'
