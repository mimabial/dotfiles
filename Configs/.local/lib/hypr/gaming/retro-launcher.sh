#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_runtime_require rofi
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"
source "${HYPR_LIB_DIR}/install/lib/desktop-entry.bash"

LIBRETRO_CORE_DIR=/usr/lib/libretro
LIBRETRO_CORE_SUFFIX=_libretro.so
RETROARCH_LAUNCHER_MARKER='X-Hypr-RetroArch=true'

usage() {
  printf 'Usage: hyprshell gaming/retro-launcher.sh install [CORE ROM] | remove\n'
}

remove_retroarch_launcher() {
  local file=""
  local name=""
  local option=""
  local selection=""
  local -a files=()
  local -a options=()

  while IFS= read -r -d '' file; do
    grep -Eq "^${RETROARCH_LAUNCHER_MARKER}\$|^Exec=retroarch[[:space:]].*-L[[:space:]]" "${file}" || continue
    name="$(sed -n 's/^Name=//p' "${file}" | head -n 1)"
    files+=("${file}")
    options+=("${name:-${file##*/}} — ${file##*/}")
  done < <(find "${DESKTOP_ENTRY_DIR}" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)

  ((${#files[@]})) || { dunstify -i dialog-information 'RetroArch launchers' 'No game launchers found'; return 0; }
  selection="$(printf '%s\n' "${options[@]}" | rofi_pick 'Remove RetroArch launcher')" || return 0
  for option in "${!options[@]}"; do
    [[ "${options[${option}]}" == "${selection}" ]] || continue
    if command -v gio >/dev/null 2>&1; then
      gio trash "${files[${option}]}"
    else
      rm -f -- "${files[${option}]}"
    fi
    update-desktop-database "${DESKTOP_ENTRY_DIR}" >/dev/null 2>&1 || true
    dunstify -i user-trash 'RetroArch launcher removed' "${selection%% — *}"
    return 0
  done
}

install_retroarch_launcher() {
  local core="" core_path="" game_path="" rom="" rom_dir="${HOME}/Games/roms"
  local game_name="" desktop_id="" desktop_file="" temp_file=""
  local -a cores=() roms=()

  if (($# == 0)); then
    mapfile -t cores < <(find "${LIBRETRO_CORE_DIR}" -maxdepth 1 -type f -name "*${LIBRETRO_CORE_SUFFIX}" -printf '%f\n' 2>/dev/null | sed "s/${LIBRETRO_CORE_SUFFIX}\$//" | sort)
    ((${#cores[@]})) || { dunstify -u critical -i dialog-error 'No RetroArch cores found' "${LIBRETRO_CORE_DIR}"; return 1; }
    core="$(printf '%s\n' "${cores[@]}" | rofi_pick 'RetroArch core')" || return 0
    mapfile -t roms < <(find "${rom_dir}" -type f \
      \( -iname '*.7z' -o -iname '*.bin' -o -iname '*.chd' -o -iname '*.cue' -o -iname '*.gb' -o -iname '*.gba' -o -iname '*.gbc' -o -iname '*.iso' -o -iname '*.m3u' -o -iname '*.md' -o -iname '*.n64' -o -iname '*.nds' -o -iname '*.nes' -o -iname '*.pbp' -o -iname '*.sfc' -o -iname '*.smc' -o -iname '*.zip' -o -iname '*.z64' \) \
      -printf '%P\n' 2>/dev/null | sort)
    ((${#roms[@]})) || { dunstify -u critical -i dialog-error 'No ROMs found' "Put ROMs in ${rom_dir}"; return 1; }
    rom="$(printf '%s\n' "${roms[@]}" | rofi_pick 'Retro game')" || return 0
    game_path="${rom_dir}/${rom}"
  elif (($# == 2)); then
    core="$1"
    game_path="$2"
  else
    usage >&2
    return 2
  fi

  [[ "${core}" == */* ]] && core_path="${core}" || core_path="${LIBRETRO_CORE_DIR}/${core}${LIBRETRO_CORE_SUFFIX}"
  [[ -f "${core_path}" ]] || { printf 'Core not found: %s\n' "${core_path}" >&2; return 1; }
  [[ -f "${game_path}" ]] || { printf 'Game not found: %s\n' "${game_path}" >&2; return 1; }

  game_name="$(basename "${game_path}")"
  game_name="${game_name%.*}"
  game_name="$(sed -E 's/[[:space:]]*\([^)]*\)//g; s/[[:space:]]+/ /g; s/^ | $//g' <<<"${game_name}")"
  desktop_id="$(tr '[:upper:]' '[:lower:]' <<<"${game_name}" | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//')"
  desktop_file="${DESKTOP_ENTRY_DIR}/retroarch-${desktop_id}.desktop"
  mkdir -p "${DESKTOP_ENTRY_DIR}"
  temp_file="$(mktemp "${desktop_file}.tmp.XXXXXX")"
  {
    printf '[Desktop Entry]\nVersion=1.0\nName=%s\n' "${game_name}"
    printf 'Comment=Play %s with RetroArch\n' "${game_name}"
    printf 'Exec=retroarch -L %s %s\n' "$(desktop_entry_quote_exec_arg "${core_path}")" "$(desktop_entry_quote_exec_arg "${game_path}")"
    printf 'Terminal=false\nType=Application\nIcon=retro-gaming\nStartupNotify=true\nCategories=Game;Emulator;\n%s\n' "${RETROARCH_LAUNCHER_MARKER}"
  } >"${temp_file}"
  chmod 755 "${temp_file}"
  mv -f "${temp_file}" "${desktop_file}"
  update-desktop-database "${DESKTOP_ENTRY_DIR}" >/dev/null 2>&1 || true
  dunstify -i retro-gaming "${game_name} installed" 'Open it from the app launcher'
}

case "${1:-}" in
  install) shift; install_retroarch_launcher "$@" ;;
  remove) (($# == 1)) || { usage >&2; exit 2; }; remove_retroarch_launcher ;;
  -h | --help) usage ;;
  *) usage >&2; exit 2 ;;
esac
