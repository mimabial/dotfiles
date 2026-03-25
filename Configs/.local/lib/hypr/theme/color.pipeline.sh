#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# color.pipeline.sh - Palette selection, wal execution, and output deployment

declare -gA COLOR_LINKS=(
  ["colors-alacritty.toml"]="${HOME}/.config/alacritty/colors.toml"
  ["colors-kitty.conf"]="${HOME}/.config/kitty/colors.conf"
  ["colors-rofi.rasi"]="${HOME}/.config/rofi/colors.rasi"
  ["colors-wofi.css"]="${HOME}/.config/wofi/style.css"
  ["colors-waybar.css"]="${HOME}/.config/waybar/colors.css"
  ["colors-hyprland.conf"]="${HOME}/.config/hypr/themes/colors.conf"
  ["colors-hyprshade.glsl"]="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal/colors.inc"
  ["colors-gtk.css"]="${HOME}/.config/gtk-3.0/colors.css"
  ["colors-tmux.conf"]="${HOME}/.config/tmux/colors.conf"
  ["colors-rmpc.ron"]="${HOME}/.config/rmpc/themes/pywal16.ron"
  ["colors--big-rmpc.ron"]="${HOME}/.config/rmpc/themes/pywal16-big.ron"
  ["colors--small-rmpc.ron"]="${HOME}/.config/rmpc/themes/pywal16-small.ron"
  ["colors-wal.vim"]="${HOME}/.vim/colors/pywal16.vim"
  ["colors-tridactyl.css"]="${HOME}/.config/tridactyl/themes/pywal.css"
  ["colors-qutebrowser.py"]="${HOME}/.config/qutebrowser/pywal-colors.py"
)

select_palette_source() {
  PALETTE_SOURCE="wallpaper"
  PALETTE_LABEL=""
  STATE_WALLPAPER=""
  WAL_THEME_FILE=""

  if [[ "${selected_color_mode}" -eq 0 ]]; then
    PALETTE_SOURCE="theme"
  fi

  if [[ "${PALETTE_SOURCE}" == "theme" ]]; then
    if ! load_theme_palette "${THEME_KITTY_FILE}"; then
      print_log -sec "theme" -warn "palette" "missing or incomplete ${THEME_KITTY_FILE}, falling back to wallpaper"
      PALETTE_SOURCE="wallpaper"
    else
      WAL_THEME_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal/theme-${HYPR_THEME// /_}.json"
      write_wal_theme_file "${WAL_THEME_FILE}"
      WALLPAPER_IMAGE="${WAL_THEME_FILE}"
      STATE_WALLPAPER="theme:${HYPR_THEME}"
      PALETTE_LABEL="theme:${HYPR_THEME}"
    fi
  fi

  if [[ "${PALETTE_SOURCE}" == "wallpaper" ]]; then
    WALLPAPER_IMAGE="${1:-${wallpaper_image:-${wal_image}}}"

    if [[ -z "${WALLPAPER_IMAGE}" ]]; then
      WALLPAPER_IMAGE="$(resolve_wallpaper_fallback)" || {
        print_log -sec "pywal16" -err "no wallpaper"
        return 1
      }
    fi
    [[ -f "${WALLPAPER_IMAGE}" ]] || {
      print_log -sec "pywal16" -err "wallpaper not found"
      return 1
    }

    STATE_WALLPAPER="${WALLPAPER_IMAGE}"
    PALETTE_LABEL="$(basename "${WALLPAPER_IMAGE}")"
  fi

  print_log -sec "pywal16" -stat "generate" "${PALETTE_LABEL} (${resolved_color_variant})"
}

configure_wal_command() {
  if [[ "${PALETTE_SOURCE}" == "theme" ]]; then
    WAL_OPTS_BASE=("--theme" "${WAL_THEME_FILE}" "-n" "-s" "-t" "-e")
    PYWAL_BACKEND="theme"
    PYWAL_BACKEND_FALLBACKS=""
    WAL_OPTS=("${WAL_OPTS_BASE[@]}")
  else
    WAL_OPTS_BASE=("-i" "${WALLPAPER_IMAGE}" "-n" "-s" "-t" "-e")
    [[ "${resolved_color_variant}" == "light" ]] && WAL_OPTS_BASE+=("-l")

    PYWAL_BACKEND="${PYWAL_BACKEND:-wal}"
    PYWAL_BACKEND_FALLBACKS="${PYWAL_BACKEND_FALLBACKS:-colorthief haishoku colorz}"
    WAL_OPTS=("${WAL_OPTS_BASE[@]}" "--backend" "${PYWAL_BACKEND}")
  fi
}

run_wal_generation() {
  if [[ "${PALETTE_SOURCE}" == "theme" ]]; then
    wal_output=$(XDG_CACHE_HOME="${WAL_XDG_CACHE_HOME}" wal "${WAL_OPTS[@]}" 2>&1)
    wal_exit=$?
  else
    local backend
    declare -A backend_seen=()
    backend_list=()
    backend_list+=("${PYWAL_BACKEND}")
    backend_seen["${PYWAL_BACKEND}"]=1

    if [[ -n "${PYWAL_BACKEND_FALLBACKS}" ]]; then
      for backend in ${PYWAL_BACKEND_FALLBACKS//,/ }; do
        [[ -n "${backend}" ]] || continue
        [[ -n "${backend_seen[$backend]:-}" ]] && continue
        backend_list+=("${backend}")
        backend_seen["${backend}"]=1
      done
    fi

    wal_exit=1
    for backend in "${backend_list[@]}"; do
      WAL_OPTS=("${WAL_OPTS_BASE[@]}" "--backend" "${backend}")
      wal_output=$(XDG_CACHE_HOME="${WAL_XDG_CACHE_HOME}" wal "${WAL_OPTS[@]}" 2>&1)
      wal_exit=$?
      if [[ "${wal_exit}" -eq 0 ]]; then
        if [[ "${backend}" != "${PYWAL_BACKEND}" ]]; then
          print_log -sec "pywal16" -warn "backend" "fallback to ${backend}"
        fi
        PYWAL_BACKEND="${backend}"
        break
      fi
    done
  fi

  [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]] && wal_cache_populate=1
}

post_process_generated_color_files() {
  if [[ -f "${WAL_CACHE}/colors-hyprshade.glsl" ]]; then
    source "${WAL_CACHE}/colors-shell.sh"
    sed_args=()
    for i in {0..15}; do
      var="color${i}"
      hex="${!var#\#}"
      r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
      sed_args+=(-e "s/COLOR${i}_RGB/${r}, ${g}, ${b}/g")
    done
    bg_hex="${background#\#}" fg_hex="${foreground#\#}"
    sed_args+=(-e "s/BACKGROUND_RGB/$((16#${bg_hex:0:2})), $((16#${bg_hex:2:2})), $((16#${bg_hex:4:2}))/g")
    sed_args+=(-e "s/FOREGROUND_RGB/$((16#${fg_hex:0:2})), $((16#${fg_hex:2:2})), $((16#${fg_hex:4:2}))/g")
    sed -i "${sed_args[@]}" "${WAL_CACHE}/colors-hyprshade.glsl"
  fi

  if [[ -f "${WAL_CACHE}/colors-rmpc.ron" ]]; then
    source "${WAL_CACHE}/colors-shell.sh"
    hex0="${color0#\#}" hex15="${color15#\#}" hex4="${color4#\#}"
    sed -i \
      -e "s/COLOR0_R/$((16#${hex0:0:2}))/g" -e "s/COLOR0_G/$((16#${hex0:2:2}))/g" -e "s/COLOR0_B/$((16#${hex0:4:2}))/g" \
      -e "s/COLOR15_R/$((16#${hex15:0:2}))/g" -e "s/COLOR15_G/$((16#${hex15:2:2}))/g" -e "s/COLOR15_B/$((16#${hex15:4:2}))/g" \
      -e "s/COLOR4_R/$((16#${hex4:0:2}))/g" -e "s/COLOR4_G/$((16#${hex4:2:2}))/g" -e "s/COLOR4_B/$((16#${hex4:4:2}))/g" \
      "${WAL_CACHE}/colors-rmpc.ron"
  fi

  if [[ -f "${WAL_CACHE}/colors-hyprland.conf" ]]; then
    source "${WAL_CACHE}/colors-shell.sh"
    sed_args=()
    for i in 0 4 7 8 15; do
      var="color${i}"
      hex="${!var#\#}"
      r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
      sed_args+=(-e "s/COLOR${i}_RGB/${r},${g},${b}/g")
    done
    sed -i "${sed_args[@]}" "${WAL_CACHE}/colors-hyprland.conf"
  fi
}

link_generated_color_files() {
  print_log -sec "pywal16" -stat "linking" "creating symlinks to color files"

  local cache_file source target
  for cache_file in "${!COLOR_LINKS[@]}"; do
    if [[ "${selected_color_mode}" -eq 0 ]] && [[ "${cache_file}" == "colors-hyprland.conf" ]]; then
      continue
    fi
    if [[ "${SKIP_WAYBAR_UPDATE}" -eq 1 ]] && [[ "${cache_file}" == "colors-waybar.css" ]]; then
      continue
    fi

    source="${WAL_CACHE}/${cache_file}"
    target="${COLOR_LINKS[$cache_file]}"
    if [[ -f "${source}" ]]; then
      mkdir -p "$(dirname "${target}")"
      if ln -sf "${source}" "${target}"; then
        [[ "${LOG_LEVEL}" == "debug" ]] && print_log -sec "symlink" -stat "linked" "${cache_file}"
      else
        print_log -sec "symlink" -warn "failed" "could not link ${cache_file}"
      fi
    else
      [[ "${LOG_LEVEL}" == "debug" ]] && print_log -sec "symlink" -warn "skip" "${cache_file} not generated"
    fi
  done
}

queue_opposite_mode_precache() {
  if [[ "${CACHE_ONLY}" -eq 1 ]] || [[ "${selected_color_mode}" -eq 0 ]] || [[ "${HYPR_WAL_CACHE_ENABLE}" -ne 1 ]]; then
    return 0
  fi

  local opposite_mode=""
  [[ "${resolved_color_variant}" == "dark" ]] && opposite_mode="light"
  [[ "${resolved_color_variant}" == "light" ]] && opposite_mode="dark"

  if [[ -n "${opposite_mode}" ]] && [[ -n "${wall_hash:-}" ]]; then
    local opposite_cache_key="${wall_hash}_${opposite_mode}_${PYWAL_BACKEND}${template_hash_suffix}"
    local opposite_cache_path="${HYPR_WAL_CACHE_DIR}/${opposite_cache_key}"

    if ! wal_cache_valid "${opposite_cache_path}"; then
      print_log -sec "pywal16" -stat "precache" "queuing ${opposite_mode} mode"
      PRECACHE_ENABLED=1
      PRECACHE_MODE="${opposite_mode}"
      PRECACHE_WALLPAPER="${WALLPAPER_IMAGE}"
    fi
  fi
}
