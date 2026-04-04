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
)

select_palette_source() {
  local theme_bg="" theme_fg="" theme_cursor=""
  local -a theme_colors=()

  PALETTE_SOURCE="wallpaper"
  PALETTE_LABEL=""
  STATE_WALLPAPER=""
  WAL_THEME_FILE=""

  if [[ "${selected_color_mode}" -eq 0 ]]; then
    PALETTE_SOURCE="theme"
  fi

  if [[ "${PALETTE_SOURCE}" == "theme" ]]; then
    if ! load_theme_palette "${THEME_KITTY_FILE}" theme_bg theme_fg theme_cursor theme_colors; then
      print_log -sec "theme" -warn "palette" "missing or incomplete ${THEME_KITTY_FILE}, falling back to wallpaper"
      PALETTE_SOURCE="wallpaper"
    else
      WAL_THEME_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal/theme-${HYPR_THEME// /_}.json"
      write_wal_theme_file "${WAL_THEME_FILE}" "${theme_bg}" "${theme_fg}" "${theme_cursor}" theme_colors
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

resolve_pywal_setting() {
  local setting="$1"
  local variant="${2:-${resolved_color_variant:-dark}}"
  local default_value
  local variant_upper="${variant^^}"
  local variant_var="PYWAL_${variant_upper}_${setting}"
  local global_var="PYWAL_${setting}"
  default_value="$(pywal_default_setting "${setting}" "${variant}")"
  local resolved_value="${!variant_var:-${!global_var:-${default_value}}}"
  printf '%s' "${resolved_value}"
}

pywal_default_setting() {
  local setting="$1"
  local variant="${2:-dark}"

  case "${variant}:${setting}" in
    light:BACKEND) printf '%s' "haishoku" ;;
    light:BACKEND_FALLBACKS) printf '%s' "colorthief wal" ;;
    light:CONTRAST) printf '%s' "1.0" ;;
    light:SATURATE) printf '%s' "0.6" ;;
    light:COLS16) printf '%s' "lighten" ;;
    dark:BACKEND) printf '%s' "colorthief" ;;
    dark:BACKEND_FALLBACKS) printf '%s' "wal haishoku" ;;
    dark:CONTRAST) printf '%s' "3.0" ;;
    dark:SATURATE) printf '%s' "0.4" ;;
    dark:COLS16) printf '%s' "lighten" ;;
    light:*) pywal_default_setting "${setting}" "dark" ;;
    dark:*) return 1 ;;
    *) pywal_default_setting "${setting}" "dark" ;;
  esac
}

compute_legibility_suffix() {
  # Build a cache-key suffix from the effective legibility settings so
  # variant-specific pywal defaults produce distinct cache entries.
  local variant="${1:-${resolved_color_variant:-dark}}"
  local contrast
  local saturate
  local cols16
  contrast="$(resolve_pywal_setting "CONTRAST" "${variant}")"
  saturate="$(resolve_pywal_setting "SATURATE" "${variant}")"
  cols16="$(resolve_pywal_setting "COLS16" "${variant}")"

  local suffix=""
  [[ -n "${contrast}" ]] && suffix+="_c${contrast}"
  [[ -n "${saturate}" ]] && suffix+="_s${saturate}"
  [[ -n "${cols16}" ]] && suffix+="_m${cols16}"
  printf '%s' "${suffix}"
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

    PYWAL_BACKEND="$(resolve_pywal_setting "BACKEND")"
    PYWAL_BACKEND_FALLBACKS="$(resolve_pywal_setting "BACKEND_FALLBACKS")"

    local wal_contrast
    local wal_saturate
    local wal_cols16
    wal_contrast="$(resolve_pywal_setting "CONTRAST")"
    wal_saturate="$(resolve_pywal_setting "SATURATE")"
    wal_cols16="$(resolve_pywal_setting "COLS16")"

    [[ -n "${wal_contrast}" ]] && WAL_OPTS_BASE+=("--contrast" "${wal_contrast}")
    [[ -n "${wal_saturate}" ]] && WAL_OPTS_BASE+=("--saturate" "${wal_saturate}")
    [[ -n "${wal_cols16}" ]] && WAL_OPTS_BASE+=("--cols16" "${wal_cols16}")

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

canonicalize_shell_colors_file() {
  local shell_file="${WAL_CACHE}/colors-shell.sh"
  local legacy_file="${WAL_CACHE}/colors.sh"

  if [[ ! -f "${shell_file}" && -f "${legacy_file}" ]]; then
    mv -f "${legacy_file}" "${shell_file}"
    return 0
  fi

  if [[ -f "${shell_file}" && -f "${legacy_file}" ]]; then
    if ! cmp -s "${shell_file}" "${legacy_file}"; then
      if [[ "${legacy_file}" -nt "${shell_file}" ]]; then
        cp -f "${legacy_file}" "${shell_file}"
      else
        print_log -sec "pywal16" -warn "colors" "discarding stale legacy colors.sh"
      fi
    fi
    rm -f "${legacy_file}"
  fi
}

hex_triplet_to_rgb_components() {
  local hex="${1#\#}"
  local r_name="$2"
  local g_name="$3"
  local b_name="$4"
  local -n r_ref="${r_name}"
  local -n g_ref="${g_name}"
  local -n b_ref="${b_name}"

  if [[ ! "${hex}" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    r_ref=0
    g_ref=0
    b_ref=0
    return 1
  fi

  r_ref=$((16#${hex:0:2}))
  g_ref=$((16#${hex:2:2}))
  b_ref=$((16#${hex:4:2}))
}

resolve_named_color_rgb() {
  local color_name="$1"
  local hex_value="$2"
  local r_name="$3"
  local g_name="$4"
  local b_name="$5"
  local -n r_ref="${r_name}"
  local -n g_ref="${g_name}"
  local -n b_ref="${b_name}"

  if ! hex_triplet_to_rgb_components "${hex_value}" r_ref g_ref b_ref; then
    print_log -sec "pywal16" -warn "colors" "invalid ${color_name} in colors-shell.sh"
  fi
}

append_rgb_placeholder_rewrites() {
  local args_name="$1"
  local placeholder="$2"
  local rewrite_mode="$3"
  local separator="$4"
  local r="$5"
  local g="$6"
  local b="$7"
  local -n args_ref="${args_name}"

  case "${rewrite_mode}" in
    triplet)
      args_ref+=(-e "s/${placeholder}/${r}${separator}${g}${separator}${b}/g")
      ;;
    components)
      args_ref+=(
        -e "s/${placeholder}_R/${r}/g"
        -e "s/${placeholder}_G/${g}/g"
        -e "s/${placeholder}_B/${b}/g"
      )
      ;;
  esac
}

rewrite_rgb_placeholders() {
  local target_file="$1"
  local rewrite_mode="$2"
  local separator="$3"
  shift 3

  local entry=""
  local placeholder=""
  local color_name=""
  local hex_value=""
  local r=0
  local g=0
  local b=0
  local -a sed_args=()

  [[ -f "${target_file}" ]] || return 0

  for entry in "$@"; do
    IFS=: read -r placeholder color_name <<<"${entry}"
    hex_value="${!color_name:-}"
    resolve_named_color_rgb "${color_name}" "${hex_value}" r g b
    append_rgb_placeholder_rewrites sed_args "${placeholder}" "${rewrite_mode}" "${separator}" "${r}" "${g}" "${b}"
  done

  sed -i "${sed_args[@]}" "${target_file}"
}

rewrite_hyprshade_colors() {
  local i=0
  local -a entries=()

  for i in {0..15}; do
    entries+=("COLOR${i}_RGB:color${i}")
  done
  entries+=("BACKGROUND_RGB:background" "FOREGROUND_RGB:foreground")

  rewrite_rgb_placeholders "${WAL_CACHE}/colors-hyprshade.glsl" triplet ", " "${entries[@]}"
}

rewrite_rmpc_colors() {
  rewrite_rgb_placeholders \
    "${WAL_CACHE}/colors-rmpc.ron" \
    components \
    "" \
    "COLOR0:color0" \
    "COLOR15:color15" \
    "COLOR4:color4"
}

rewrite_hyprland_colors() {
  rewrite_rgb_placeholders \
    "${WAL_CACHE}/colors-hyprland.conf" \
    triplet \
    "," \
    "COLOR0_RGB:color0" \
    "COLOR4_RGB:color4" \
    "COLOR7_RGB:color7" \
    "COLOR8_RGB:color8" \
    "COLOR15_RGB:color15"
}

post_process_generated_color_files() {
  local colors_shell="${WAL_CACHE}/colors-shell.sh"

  if [[ -f "${WAL_CACHE}/colors-hyprshade.glsl" || -f "${WAL_CACHE}/colors-rmpc.ron" || -f "${WAL_CACHE}/colors-hyprland.conf" ]]; then
    source "${colors_shell}"
  fi

  rewrite_hyprshade_colors
  rewrite_rmpc_colors
  rewrite_hyprland_colors
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

  local waybar_palette_helper="${SCRIPT_DIR}/waybar_palette.py"
  if [[ "${SKIP_WAYBAR_UPDATE}" -ne 1 ]] && [[ -f "${WAL_CACHE}/colors-waybar.css" ]] && [[ -x "${waybar_palette_helper}" ]]; then
    python3 "${waybar_palette_helper}" "${WAL_CACHE}/colors-waybar.css" \
      || print_log -sec "waybar" -warn "palette" "failed to refine semantic colors"
  fi
}

queue_opposite_mode_precache() {
  if [[ "${CACHE_ONLY}" -eq 1 ]] || [[ "${selected_color_mode}" -eq 0 ]] || [[ "${HYPR_WAL_CACHE_ENABLE}" -ne 1 ]]; then
    return 0
  fi

  local opposite_mode=""
  [[ "${resolved_color_variant}" == "dark" ]] && opposite_mode="light"
  [[ "${resolved_color_variant}" == "light" ]] && opposite_mode="dark"

  if [[ -n "${opposite_mode}" ]] && [[ -n "${wall_hash:-}" ]]; then
    local leg_suffix
    local opposite_backend
    opposite_backend="$(resolve_pywal_setting "BACKEND" "${opposite_mode}")"
    leg_suffix="$(compute_legibility_suffix "${opposite_mode}")"
    local opposite_cache_key="${wall_hash}_${opposite_mode}_${opposite_backend}${leg_suffix}${template_hash_suffix}"
    local opposite_cache_path="${HYPR_WAL_CACHE_DIR}/${opposite_cache_key}"

    if ! wal_cache_valid "${opposite_cache_path}"; then
      print_log -sec "pywal16" -stat "precache" "queuing ${opposite_mode} mode"
      PRECACHE_ENABLED=1
      PRECACHE_MODE="${opposite_mode}"
      PRECACHE_WALLPAPER="${WALLPAPER_IMAGE}"
    fi
  fi
}
