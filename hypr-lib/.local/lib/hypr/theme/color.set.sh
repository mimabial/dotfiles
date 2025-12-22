#!/usr/bin/env bash
# shellcheck disable=SC2154,SC1091

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
elif ! declare -F print_log >/dev/null; then
  LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
  if [[ -r "${LIB_DIR}/hypr/globalcontrol.sh" ]]; then
    # shellcheck disable=SC1090
    source "${LIB_DIR}/hypr/globalcontrol.sh"
  fi
fi
if declare -F export_hypr_config >/dev/null; then
  export_hypr_config
fi

# Lockfile for process synchronization
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/color-gen.lock"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/color.gen.state"
# Signal file for waybar watcher
THEME_UPDATE_LOCK="${XDG_RUNTIME_DIR:-/tmp}/theme-update.lock"
CACHE_ONLY="${HYPR_WAL_CACHE_ONLY:-0}"
ASYNC_APPS="${HYPR_WAL_ASYNC_APPS:-0}"
MODE_OVERRIDE="${HYPR_WAL_MODE_OVERRIDE:-}"
CACHE_ONLY_ROOT=""
mkdir -p "$(dirname "$LOCK_FILE")" "$(dirname "$STATE_FILE")"

exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
  if [[ "${CACHE_ONLY}" -eq 1 ]]; then
    print_log -sec "pywal16" -stat "skip" "cache-only: another process running"
    exit 0
  fi
  print_log -sec "pywal16" -stat "wait" "Another process running"
  flock 200
fi

# Create theme update lock to prevent waybar from reacting to intermediate changes
if [[ "${CACHE_ONLY}" -ne 1 ]]; then
  touch "${THEME_UPDATE_LOCK}"
fi

# Setup EXIT trap handler to run all cleanup tasks
cleanup() {
  if [[ -n "${CACHE_ONLY_ROOT}" ]]; then
    rm -rf "${CACHE_ONLY_ROOT}" 2>/dev/null || true
  fi
  if [[ "${CACHE_ONLY}" -ne 1 ]]; then
    rm -f "${THEME_UPDATE_LOCK}"
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && hyprctl reload config-only -q
  fi
}
trap cleanup EXIT

# Disable Hyprland autoreload during theme application
[[ -n $HYPRLAND_INSTANCE_SIGNATURE && "${CACHE_ONLY}" -ne 1 ]] && hyprctl keyword misc:disable_autoreload 1 -q

# Get mode from state
dcol_mode="${dcol_mode:-dark}"
if [[ -z "${MODE_OVERRIDE}" ]] && [ -f "$HYPR_STATE_HOME/mode" ]; then
  dcol_mode=$(cat "$HYPR_STATE_HOME/mode")
fi

# Check enableWallDcol (0=theme, 1=auto, 2=dark, 3=light)
[ -f "$HYPR_STATE_HOME/config" ] && source "$HYPR_STATE_HOME/config"
enableWallDcol="${enableWallDcol:-1}"

# Always determine current theme (needed for Kvantum in both modes)
if [ -z "${HYPR_THEME}" ]; then
  # Try to read from wal.conf
  WAL_CONF="${HYPR_CONFIG_HOME}/themes/wal.conf"
  if [ -f "${WAL_CONF}" ]; then
    HYPR_THEME=$(grep '^\$HYPR_THEME=' "${WAL_CONF}" | cut -d'=' -f2)
  fi

  # Fallback to first theme if still not set
  if [ -z "${HYPR_THEME}" ]; then
    if [ -d "${HYPR_CONFIG_HOME}/themes" ]; then
      HYPR_THEME=$(find "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d | sort | head -1 | xargs basename)
    fi
  fi
fi

# Set HYPR_THEME_DIR if we have a theme
if [ -n "${HYPR_THEME}" ] && [ -z "${HYPR_THEME_DIR}" ]; then
  export HYPR_THEME="${HYPR_THEME}"
  export HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  print_log -sec "theme" -stat "detected" "${HYPR_THEME}"
fi

SKIP_WAYBAR_UPDATE="${SKIP_WAYBAR_UPDATE:-0}"

# Override mode based on enableWallDcol
case "${enableWallDcol}" in
  2) dcol_mode="dark" ;;
  3) dcol_mode="light" ;;
esac
if [[ -n "${MODE_OVERRIDE}" ]]; then
  case "${MODE_OVERRIDE}" in
    dark | light) dcol_mode="${MODE_OVERRIDE}" ;;
    *) print_log -sec "pywal16" -warn "mode" "invalid override: ${MODE_OVERRIDE}" ;;
  esac
fi

WAL_XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
if [[ "${CACHE_ONLY}" -eq 1 ]]; then
  CACHE_ONLY_ROOT_BASE="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
  CACHE_ONLY_ROOT="$(mktemp -d -p "${CACHE_ONLY_ROOT_BASE}" "wal-cache-only.XXXXXXXX")" || {
    print_log -sec "pywal16" -err "cache" "temp dir failed"
    exit 1
  }
  WAL_XDG_CACHE_HOME="${CACHE_ONLY_ROOT}"
fi
WAL_CACHE="${WAL_XDG_CACHE_HOME}/wal"
mkdir -p "${WAL_CACHE}"

# Centralized color file symlink definitions
declare -gA COLOR_LINKS=(
  ["colors-alacritty.toml"]="${HOME}/.config/alacritty/colors.toml"
  ["colors-kitty.conf"]="${HOME}/.config/kitty/colors.conf"
  ["colors-rofi.rasi"]="${HOME}/.config/rofi/colors.rasi"
  ["colors-wofi.css"]="${HOME}/.config/wofi/style.css"
  ["colors-walker.css"]="${HOME}/.config/walker/themes/pywal16/style.css"
  ["colors-waybar.css"]="${HOME}/.config/waybar/colors.css"
  ["colors-swaync.css"]="${HOME}/.config/swaync/colors.css"
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

# Generate colors from wallpaper (always, even in theme mode)
WALLPAPER_IMAGE="${1:-${wallpaper_image:-${wal_image}}}"

[ -z "${WALLPAPER_IMAGE}" ] && {
  print_log -sec "pywal16" -err "no wallpaper"
  exit 1
}
[ ! -f "${WALLPAPER_IMAGE}" ] && {
  print_log -sec "pywal16" -err "wallpaper not found"
  exit 1
}

print_log -sec "pywal16" -stat "generate" "$(basename "${WALLPAPER_IMAGE}") (${dcol_mode})"

# Build pywal16 command
WAL_OPTS_BASE=("-i" "${WALLPAPER_IMAGE}" "-n" "-s" "-t" "-e")
[ "${dcol_mode}" == "light" ] && WAL_OPTS_BASE+=("-l")

# Use haishoku backend by default; fall back to others on failure.
# Override with PYWAL_BACKEND / PYWAL_BACKEND_FALLBACKS.
PYWAL_BACKEND="${PYWAL_BACKEND:-wal}"
PYWAL_BACKEND_FALLBACKS="${PYWAL_BACKEND_FALLBACKS:-colorthief haishoku colorz}"
WAL_OPTS=("${WAL_OPTS_BASE[@]}" "--backend" "${PYWAL_BACKEND}")

# Cache pywal output per wallpaper hash + mode (avoids rerunning wal on repeats)
HYPR_WAL_CACHE_ENABLE="${HYPR_WAL_CACHE_ENABLE:-1}"
HYPR_WAL_CACHE_DIR="${HYPR_WAL_CACHE_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wal/cache}"
wal_cache_key=""
wal_cache_path=""
wal_cache_populate=0

wal_cache_swap_dir() {
  local src_dir="${1}"
  local dest_dir="${2}"

  [[ -d "${src_dir}" ]] || return 1
  [[ -n "${dest_dir}" ]] || return 1

  local dest_parent tmp_dir backup_dir schemes_tmp post_hooks_tmp
  dest_parent="$(dirname "${dest_dir}")"
  mkdir -p "${dest_parent}"

  tmp_dir="$(mktemp -d -p "${dest_parent}" wal.swap.XXXXXXXX)" || return 1
  if ! cp -a --reflink=auto "${src_dir}/." "${tmp_dir}/" 2>/dev/null; then
    cp -a "${src_dir}/." "${tmp_dir}/" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
  fi
  rm -f "${tmp_dir}/.complete" "${tmp_dir}/.meta" 2>/dev/null || true

  if [[ -e "${dest_dir}" ]] && [[ ! -d "${dest_dir}" ]]; then
    rm -f "${dest_dir}" 2>/dev/null || true
  fi

  if [[ -d "${dest_dir}" ]]; then
    # Preserve wal history + user hooks across cache restores.
    schemes_tmp=""
    post_hooks_tmp=""
    if [[ -d "${dest_dir}/schemes" ]]; then
      schemes_tmp="${dest_parent}/wal.schemes.$$"
      mv "${dest_dir}/schemes" "${schemes_tmp}" 2>/dev/null || schemes_tmp=""
    fi
    if [[ -f "${dest_dir}/post-hooks.sh" ]]; then
      post_hooks_tmp="${dest_parent}/wal.post-hooks.$$"
      mv "${dest_dir}/post-hooks.sh" "${post_hooks_tmp}" 2>/dev/null || post_hooks_tmp=""
    fi

    backup_dir="${dest_dir}.bak.$$"
    mv "${dest_dir}" "${backup_dir}" 2>/dev/null || {
      [[ -n "${schemes_tmp}" ]] && [[ -d "${schemes_tmp}" ]] && mv "${schemes_tmp}" "${dest_dir}/schemes" 2>/dev/null || true
      [[ -n "${post_hooks_tmp}" ]] && [[ -f "${post_hooks_tmp}" ]] && mv "${post_hooks_tmp}" "${dest_dir}/post-hooks.sh" 2>/dev/null || true
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      mv "${backup_dir}" "${dest_dir}" 2>/dev/null || true
      [[ -n "${schemes_tmp}" ]] && [[ -d "${schemes_tmp}" ]] && mv "${schemes_tmp}" "${dest_dir}/schemes" 2>/dev/null || true
      [[ -n "${post_hooks_tmp}" ]] && [[ -f "${post_hooks_tmp}" ]] && mv "${post_hooks_tmp}" "${dest_dir}/post-hooks.sh" 2>/dev/null || true
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }

    [[ -n "${schemes_tmp}" ]] && [[ -d "${schemes_tmp}" ]] && mv "${schemes_tmp}" "${dest_dir}/schemes" 2>/dev/null || true
    [[ -n "${post_hooks_tmp}" ]] && [[ -f "${post_hooks_tmp}" ]] && mv "${post_hooks_tmp}" "${dest_dir}/post-hooks.sh" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
  else
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
  fi
}

wal_cache_valid() {
  local dir="${1}"
  [[ -f "${dir}/.complete" ]] || return 1
  [[ -f "${dir}/colors.json" ]] || return 1
  [[ -f "${dir}/colors-shell.sh" ]] || return 1
  return 0
}

wal_used_cache=0
wal_output=""
wal_exit=""

if [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]]; then
  mkdir -p "${HYPR_WAL_CACHE_DIR}" 2>/dev/null || true
  wall_hash="$(${hashMech:-sha1sum} "${WALLPAPER_IMAGE}" | awk '{print $1}')"
  wal_cache_key="${wall_hash}_${dcol_mode}_${PYWAL_BACKEND}"
  wal_cache_path="${HYPR_WAL_CACHE_DIR}/${wal_cache_key}"
  wal_cache_backend="${PYWAL_BACKEND}"

  prev_key=""
  prev_colormode=""
  if [[ -r "${STATE_FILE}" ]]; then
    prev_key="$(head -n 1 "${STATE_FILE}" 2>/dev/null || true)"
    prev_colormode="$(awk -F= '/^colormode=/{print $2; exit}' "${STATE_FILE}")"
  fi

  allow_fast_path=0
  if [[ "${FORCE_COLOR_REGEN:-0}" -ne 1 ]] && [[ "${enableWallDcol}" -ne 0 ]]; then
    if [[ "${prev_colormode}" =~ ^[0-9]+$ ]] && [[ "${prev_colormode}" -ne 0 ]]; then
      allow_fast_path=1
    fi
  fi

  if [[ "${prev_key}" == "${wal_cache_key}" ]]; then
    # Fast-path: wallpaper unchanged, skip pywal and downstream work
    # Only safe in wallpaper mode if the previous run was also wallpaper mode.
    if [[ "${allow_fast_path}" -eq 1 ]]; then
      print_log -sec "pywal16" -stat "cache" "current (fast-path)"
      rm -f "${THEME_UPDATE_LOCK}"
      exit 0
    fi
    wal_used_cache=1
    wal_exit=0
    print_log -sec "pywal16" -stat "cache" "current"
  elif wal_cache_valid "${wal_cache_path}"; then
    print_log -sec "pywal16" -stat "cache" "hit"
    if wal_cache_swap_dir "${wal_cache_path}" "${WAL_CACHE}"; then
      wal_used_cache=1
      wal_exit=0
    else
      print_log -sec "pywal16" -warn "cache" "restore failed, regenerating"
      wal_exit=""
    fi
  fi
fi

if [[ -z "${wal_exit}" ]]; then
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

  [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]] && wal_cache_populate=1
fi

if [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]] && [[ -n "${wall_hash:-}" ]] && [[ "${wal_cache_backend:-}" != "${PYWAL_BACKEND}" ]]; then
  wal_cache_key="${wall_hash}_${dcol_mode}_${PYWAL_BACKEND}"
  wal_cache_path="${HYPR_WAL_CACHE_DIR}/${wal_cache_key}"
fi

[[ "${LOG_LEVEL}" == "debug" ]] && echo "${wal_output}" | while read -r line; do
  print_log -sec "pywal16" -stat "debug" "${line}"
done

[ $wal_exit -ne 0 ] && {
  print_log -sec "pywal16" -err "failed"
  echo "${wal_output}" >&2
  exit 1
}

print_log -sec "pywal16" -stat "complete" "color generation"

# Generate hyprlock integer rgba colors
if [ -f "${LIB_DIR}/hypr/wal/wal.hyprlock.sh" ]; then
  bash "${LIB_DIR}/hypr/wal/wal.hyprlock.sh"
  print_log -sec "hyprlock" -stat "generated" "integer rgba colors"
fi

# Post-process RGB-dependent templates
# Convert hex colors to RGB for hyprshade.glsl
if [ -f "${WAL_CACHE}/colors-hyprshade.glsl" ]; then
  source "${WAL_CACHE}/colors-shell.sh"
  for i in {0..15}; do
    eval "hex=\$color$i"
    hex="${hex#\#}"
    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    sed -i "s/COLOR${i}_RGB/${r}, ${g}, ${b}/g" "${WAL_CACHE}/colors-hyprshade.glsl"
  done
  # Background and foreground
  bg_hex="${background#\#}"
  fg_hex="${foreground#\#}"
  sed -i "s/BACKGROUND_RGB/$((16#${bg_hex:0:2})), $((16#${bg_hex:2:2})), $((16#${bg_hex:4:2}))/g" "${WAL_CACHE}/colors-hyprshade.glsl"
  sed -i "s/FOREGROUND_RGB/$((16#${fg_hex:0:2})), $((16#${fg_hex:2:2})), $((16#${fg_hex:4:2}))/g" "${WAL_CACHE}/colors-hyprshade.glsl"
fi

# Convert hex colors to RGB for rmpc.ron
if [ -f "${WAL_CACHE}/colors-rmpc.ron" ]; then
  source "${WAL_CACHE}/colors-shell.sh"
  # color0 (background)
  hex="${color0#\#}"
  sed -i "s/COLOR0_R/$((16#${hex:0:2}))/g; s/COLOR0_G/$((16#${hex:2:2}))/g; s/COLOR0_B/$((16#${hex:4:2}))/g" "${WAL_CACHE}/colors-rmpc.ron"
  # color15 (foreground)
  hex="${color15#\#}"
  sed -i "s/COLOR15_R/$((16#${hex:0:2}))/g; s/COLOR15_G/$((16#${hex:2:2}))/g; s/COLOR15_B/$((16#${hex:4:2}))/g" "${WAL_CACHE}/colors-rmpc.ron"
  # color4 (highlight)
  hex="${color4#\#}"
  sed -i "s/COLOR4_R/$((16#${hex:0:2}))/g; s/COLOR4_G/$((16#${hex:2:2}))/g; s/COLOR4_B/$((16#${hex:4:2}))/g" "${WAL_CACHE}/colors-rmpc.ron"
fi

# Convert hex colors to RGB for hyprland rgba variables
if [ -f "${WAL_CACHE}/colors-hyprland.conf" ]; then
  source "${WAL_CACHE}/colors-shell.sh"
  for i in 0 4 7 8 15; do
    var="color${i}"
    hex="${!var#\#}"
    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    sed -i "s/COLOR${i}_RGB/${r},${g},${b}/g" "${WAL_CACHE}/colors-hyprland.conf"
  done
fi

# Persist wal output into the per-wallpaper cache after post-processing.
wal_cache_store() {
  local src_dir="${1}"
  local dest_dir="${2}"

  [[ -d "${src_dir}" ]] || return 1
  [[ -n "${dest_dir}" ]] || return 1

  local dest_parent tmp_dir backup_dir
  dest_parent="$(dirname "${dest_dir}")"
  mkdir -p "${dest_parent}" 2>/dev/null || true

  tmp_dir="$(mktemp -d -p "${dest_parent}" "$(basename "${dest_dir}").tmp.XXXXXXXX")" || return 1
  while IFS= read -r -d '' entry; do
    if ! cp -a --reflink=auto "${entry}" "${tmp_dir}/" 2>/dev/null; then
      cp -a "${entry}" "${tmp_dir}/" 2>/dev/null || {
        rm -rf "${tmp_dir}" 2>/dev/null || true
        return 1
      }
    fi
  done < <(
    find "${src_dir}" -mindepth 1 -maxdepth 1 \
      ! -name "schemes" \
      ! -name "post-hooks.sh" \
      -print0 2>/dev/null
  )

  {
    echo "${wal_cache_key}"
    echo "wallpaper=${WALLPAPER_IMAGE}"
    echo "mode=${dcol_mode}"
    echo "backend=${PYWAL_BACKEND}"
  } >"${tmp_dir}/.meta"
  touch "${tmp_dir}/.complete"

  if [[ -d "${dest_dir}" ]]; then
    backup_dir="${dest_dir}.bak.$$"
    mv "${dest_dir}" "${backup_dir}" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      mv "${backup_dir}" "${dest_dir}" 2>/dev/null || true
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
    rm -rf "${backup_dir}" 2>/dev/null || true
  else
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
  fi

  print_log -sec "pywal16" -stat "cache" "stored"
}

if [[ "${wal_cache_populate}" -eq 1 ]] && [[ "${wal_used_cache}" -eq 0 ]] && [[ -n "${wal_cache_path}" ]]; then
  wal_cache_store "${WAL_CACHE}" "${wal_cache_path}" || print_log -sec "pywal16" -warn "cache" "store failed"
fi
if [[ "${CACHE_ONLY}" -eq 1 ]]; then
  print_log -sec "pywal16" -stat "cache" "prepared (cache-only)"
  exit 0
fi

# Source pywal16-generated colors
set -a
[ -f "${WAL_CACHE}/colors.sh" ] && source "${WAL_CACHE}/colors-shell.sh"
set +a

# Pywal16 generates all color files to ~/.cache/wal/
# Now create symlinks to expected locations
print_log -sec "pywal16" -stat "linking" "creating symlinks to color files"

for cache_file in "${!COLOR_LINKS[@]}"; do
  # In theme mode, Hyprland colors are derived from the theme palette (not the wallpaper).
  # Keep pywal16's cache output available, but don't link it over the theme colors.
  if [[ "${enableWallDcol}" -eq 0 ]] && [[ "${cache_file}" == "colors-hyprland.conf" ]]; then
    continue
  fi
  if [[ "${SKIP_WAYBAR_UPDATE}" -eq 1 ]] && [[ "${cache_file}" == "colors-waybar.css" ]]; then
    continue
  fi

  source="${WAL_CACHE}/${cache_file}"
  target="${COLOR_LINKS[$cache_file]}"
  if [ -f "${source}" ]; then
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

# In theme mode, ensure Hyprland `colors.conf` matches the selected theme palette.
generate_hypr_colors_from_theme() {
  local kitty_theme_file="${HYPR_THEME_DIR}/kitty.theme"
  local out_file="${HOME}/.config/hypr/themes/colors.conf"
  local tmp_file="${out_file}.tmp.$$"

  [[ -n "${HYPR_THEME_DIR}" ]] || return 1
  [[ -r "${kitty_theme_file}" ]] || {
    print_log -sec "theme" -warn "colors" "missing kitty.theme: ${kitty_theme_file}"
    return 1
  }

  local theme_bg theme_fg
  theme_bg="$(awk '$1=="background"{print $2; exit}' "${kitty_theme_file}")"
  theme_fg="$(awk '$1=="foreground"{print $2; exit}' "${kitty_theme_file}")"
  [[ "${theme_bg}" =~ ^#[0-9A-Fa-f]{6}$ ]] || theme_bg=""
  [[ "${theme_fg}" =~ ^#[0-9A-Fa-f]{6}$ ]] || theme_fg=""

  local -a theme_colors=()
  local i key val
  for i in {0..15}; do
    key="color${i}"
    val="$(awk -v key="${key}" '$1==key{print $2; exit}' "${kitty_theme_file}")"
    [[ "${val}" =~ ^#[0-9A-Fa-f]{6}$ ]] || val=""
    theme_colors[$i]="${val}"
  done

  # Require a complete palette; fall back if a theme is incomplete.
  for i in {0..15}; do
    key="color${i}"
    [[ -n "${theme_colors[$i]}" ]] || {
      print_log -sec "theme" -warn "colors" "missing ${key} in ${kitty_theme_file}"
      return 1
    }
  done

  [[ -n "${theme_bg}" ]] || theme_bg="${theme_colors[0]}"
  [[ -n "${theme_fg}" ]] || theme_fg="${theme_colors[15]}"

  local active_border inactive_border_bg inactive_border_fg
  active_border="${theme_colors[4]#\#}ff"
  inactive_border_bg="${theme_colors[0]#\#}cc"
  inactive_border_fg="${theme_colors[8]#\#}cc"

  mkdir -p "$(dirname "${out_file}")"
  [[ -L "${out_file}" ]] && rm -f "${out_file}"

  {
    echo "# Autogenerated theme colors (from kitty.theme)"
    echo "# Theme: ${HYPR_THEME}"
    echo "# Source: ${kitty_theme_file}"
    echo
    echo "# Standard theme colors"
    for i in {0..15}; do
      printf '$color%s = %s\n' "${i}" "${theme_colors[$i]}"
    done
    echo
    echo "# Hyprland-friendly helpers (no leading '#')"
    for i in {0..15}; do
      local hex="${theme_colors[$i]#\#}"
      printf '$color%see = %s\n' "${i}" "${hex}ee"
    done
    echo
    printf '$background = %s\n' "${theme_bg}"
    printf '$foreground = %s\n' "${theme_fg}"
    printf '$cursor = %s\n' "${theme_fg}"
    echo

    cat <<EOF

general {
    col.active_border = rgba(${active_border}) rgba(${active_border}) 45deg
    col.inactive_border = rgba(${inactive_border_bg}) rgba(${inactive_border_fg}) 45deg
}

group {
    col.border_active = rgba(${active_border}) rgba(${active_border}) 45deg
    col.border_inactive = rgba(${inactive_border_bg}) rgba(${inactive_border_fg}) 45deg
    col.border_locked_active = rgba(${active_border}) rgba(${active_border}) 45deg
    col.border_locked_inactive = rgba(${inactive_border_bg}) rgba(${inactive_border_fg}) 45deg
}
EOF
  } >"${tmp_file}"

  mv -f "${tmp_file}" "${out_file}"
  print_log -sec "theme" -stat "colors" "wrote ${out_file}"
}

if [[ "${enableWallDcol}" -eq 0 ]]; then
  if ! generate_hypr_colors_from_theme; then
    print_log -sec "theme" -warn "colors" "falling back to pywal16 Hyprland colors"
    ln -sf "${WAL_CACHE}/colors-hyprland.conf" "${HOME}/.config/hypr/themes/colors.conf" 2>/dev/null || true
  fi
fi

# Kvantum theme is now handled in parallel by wal.kvantum.sh

print_log -sec "pywal16" -stat "complete" "color files ready"

# Application theming - deploy generated templates (run in parallel)
print_log -sec "pywal16" -stat "deploy" "applying themes to applications"

maybe_wait() {
  if [[ "${ASYNC_APPS}" -eq 1 ]]; then
    return 0
  fi
  wait
}

# Get hypr_border early for scripts that need it
theme_conf="${HYPR_CONFIG_HOME}/themes/theme.conf"
if [ -f "${theme_conf}" ]; then
  hypr_border=$(grep "rounding" "${theme_conf}" | grep "=" | head -1 | awk '{print $NF}')
  export hypr_border
fi

# Run independent app theming scripts in parallel
[ -f "${LIB_DIR}/hypr/wal/wal.kvantum.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.kvantum.sh" &
[ -f "${LIB_DIR}/hypr/wal/wal.cava.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.cava.sh" &
[ -f "${LIB_DIR}/hypr/wal/wal.gtk.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.gtk.sh" &
[ -f "${LIB_DIR}/hypr/wal/wal.vscode.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.vscode.sh" &
[ -f "${LIB_DIR}/hypr/wal/wal.swaync.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.swaync.sh" &
[ -f "${LIB_DIR}/hypr/wal/wal.tmux.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.tmux.sh" &
[ -f "${LIB_DIR}/hypr/wal/wal.qutebrowser.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.qutebrowser.sh" &
command -v pywalfox &>/dev/null && { pywalfox update &>/dev/null && print_log -sec "pywalfox" -stat "updated" "Firefox theme"; } &

if [[ "${ASYNC_APPS}" -eq 1 ]]; then
  print_log -sec "pywal16" -stat "async" "app theming running in background"
fi

# Wait for all background app theming jobs to complete
maybe_wait

# Hyprshade color normalization (convert RGB 0-255 to 0.0-1.0 range for GLSL)
if [ -f "${cacheDir}/colors-hyprshade.glsl" ]; then
  sed -i 's/vec3(\([0-9]\+\), \([0-9]\+\), \([0-9]\+\))/vec3(\1\/255.0, \2\/255.0, \3\/255.0)/g' "${cacheDir}/colors-hyprshade.glsl"
fi

# Reload live applications
pkill -SIGUSR1 kitty 2>/dev/null                                                        # Reload kitty terminal colors
pkill -USR2 cava 2>/dev/null                                                            # Reload cava visualizer colors
tmux list-sessions &>/dev/null && tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null # Reload tmux if running

# Theme symlinks are already created at lines 99-117, no need to modify them here

# Process .theme files from theme directory
process_theme_files() {
  [ -z "${HYPR_THEME_DIR}" ] && {
    print_log -sec "theme" -warn "skip" "HYPR_THEME_DIR not set"
    return 0
  }
  [ ! -d "${HYPR_THEME_DIR}" ] && {
    print_log -sec "theme" -warn "skip" "theme directory not found: ${HYPR_THEME_DIR}"
    return 0
  }

  print_log -sec "theme" -stat "processing" ".theme files from ${HYPR_THEME}"

  # Array to collect post-write commands
  local -a post_commands=()

  # First pass: Write all files and collect commands
  while IFS= read -r theme_file; do
    [ ! -f "${theme_file}" ] && continue
    [ "$(basename "${theme_file}")" = "hypr.theme" ] && continue
    # Skip kvantum .theme files (handled separately in Kvantum section above)
    [[ "${theme_file}" =~ /kvantum/.*\.theme$ ]] && continue

    # Parse first line: target_path | exec_command
    local first_line
    first_line=$(head -1 "${theme_file}")

    # Extract target path (before pipe)
    local target_path
    target_path=$(echo "${first_line}" | cut -d'|' -f1 | xargs)

    # Expand variables in path safely (only common shell variables, no command substitution)
    target_path="${target_path//\$HOME/$HOME}"
    target_path="${target_path//\$XDG_CONFIG_HOME/${XDG_CONFIG_HOME:-$HOME/.config}}"
    target_path="${target_path//\$XDG_CACHE_HOME/${XDG_CACHE_HOME:-$HOME/.cache}}"
    target_path="${target_path//\$XDG_DATA_HOME/${XDG_DATA_HOME:-$HOME/.local/share}}"
    target_path="${target_path//\$USER/$USER}"

    # Extract exec command (after pipe, optional)
    local exec_cmd
    exec_cmd=$(echo "${first_line}" | cut -d'|' -f2 | xargs)

    # Expand variables in command safely (only whitelisted variables)
    if [ -n "${exec_cmd}" ]; then
      exec_cmd="${exec_cmd//\$HOME/$HOME}"
      exec_cmd="${exec_cmd//\$XDG_CONFIG_HOME/${XDG_CONFIG_HOME:-$HOME/.config}}"
      exec_cmd="${exec_cmd//\$XDG_CACHE_HOME/${XDG_CACHE_HOME:-$HOME/.cache}}"
      exec_cmd="${exec_cmd//\$XDG_DATA_HOME/${XDG_DATA_HOME:-$HOME/.local/share}}"
      exec_cmd="${exec_cmd//\$USER/$USER}"
      exec_cmd="${exec_cmd//\$\{scrDir\}/${scrDir:-$HOME/.local/lib/hypr}}"
      exec_cmd="${exec_cmd//\$scrDir/${scrDir:-$HOME/.local/lib/hypr}}"
      exec_cmd="${exec_cmd//\$\{LIB_DIR\}/${LIB_DIR:-$HOME/.local/lib}}"
      exec_cmd="${exec_cmd//\$LIB_DIR/${LIB_DIR:-$HOME/.local/lib}}"
    fi

    [ -z "${target_path}" ] && {
      print_log -sec "theme" -warn "skip" "no target path in $(basename "${theme_file}")"
      continue
    }

    # Create target directory
    mkdir -p "$(dirname "${target_path}")"

    # Hash-based skip: only write if content changed
    new_content="$(sed '1d' "${theme_file}")"
    new_hash="$(echo "${new_content}" | md5sum | cut -d' ' -f1)"
    old_hash=""
    [ -f "${target_path}" ] && old_hash="$(md5sum "${target_path}" 2>/dev/null | cut -d' ' -f1)"

    if [ "${new_hash}" != "${old_hash}" ]; then
      echo "${new_content}" >"${target_path}"
      print_log -sec "theme" -stat "wrote" "${target_path}"

      # Only queue exec command if file actually changed
      if [ -n "${exec_cmd}" ]; then
        if [[ "${exec_cmd}" =~ \$|\` ]]; then
          print_log -sec "theme" -warn "blocked" "command contains unexpanded variables or substitution in $(basename "${theme_file}"): ${exec_cmd}"
        else
          post_commands+=("${exec_cmd}")
        fi
      fi
    else
      [[ "${LOG_LEVEL}" == "debug" ]] && print_log -sec "theme" -stat "skip" "${target_path} (unchanged)"
    fi

  done < <(find "${HYPR_THEME_DIR}" -type f -name "*.theme" 2>/dev/null)

  # Second pass: Execute all collected commands after all files are written
  if [ ${#post_commands[@]} -gt 0 ]; then
    print_log -sec "theme" -stat "executing" "${#post_commands[@]} post-write commands"
    for cmd in "${post_commands[@]}"; do
      print_log -sec "theme" -stat "exec" "${cmd}"
      bash -c "${cmd}" &
    done
    # Wait for all background commands to complete before proceeding
    wait
    print_log -sec "theme" -stat "complete" "all post-write commands finished"
  fi

  # Note: waybar reload is handled by the watcher when THEME_UPDATE_LOCK is removed
  # The watcher batches all file change events and reloads once at the end
}

# Only process .theme files in theme mode
if [ "${enableWallDcol}" -eq 0 ]; then
  process_theme_files
else
  # In wallpaper mode, clear theme override files to prevent stale theme colors
  # Write minimal valid content to avoid parser errors during live reload
  print_log -sec "theme" -stat "cleanup" "clearing theme files (wallpaper mode)"
  : >"${HOME}/.config/waybar/theme.css"
  : >"${HOME}/.config/kitty/theme.conf"
  echo "# Empty theme file" >"${HOME}/.config/alacritty/theme.toml"
  : >"${HOME}/.config/swaync/theme.css"
  # Rofi themes expect variables like @background/@foreground; keep a valid fallback
  # that pulls from pywal16-generated ~/.config/rofi/colors.rasi.
  cat >"${HOME}/.config/rofi/theme.rasi" <<'EOF'
/* Wallpaper mode (auto/dark/light): use pywal16 colors */
@import "~/.config/rofi/colors.rasi"
* {
    separatorcolor:     transparent;
    border-color:       transparent;
}
EOF
  : >"${HOME}/.config/tmux/theme.conf"

  # Reload apps to apply cleared theme files
  # Note: waybar reload is handled by the watcher when THEME_UPDATE_LOCK is removed
  pkill -SIGUSR1 kitty 2>/dev/null
  swaync-client -rs 2>/dev/null
  tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null
fi

# Run non-critical theming operations in parallel for speed
# These don't need to block the main theme application

# Ensure ICON_THEME is set correctly before parallel operations
if command -v hyq &>/dev/null; then
  theme_conf="${HYPR_CONFIG_HOME}/themes/theme.conf"
  if [ "${enableWallDcol}" -eq 0 ] && [ -r "${theme_conf}" ]; then
    eval "$(
      hyq "${theme_conf}" --export env --allow-missing \
        -Q "\$ICON_THEME[string]"
    )"
    [ -n "${__ICON_THEME}" ] && ICON_THEME="${__ICON_THEME}"
  elif [ -z "${ICON_THEME}" ]; then
    eval "$(
      hyq "${HYPR_CONFIG_HOME}/hyprland.conf" --source --export env \
        --allow-missing \
        -Q "\$ICON_THEME[string]"
    )"
    ICON_THEME=${__ICON_THEME:-$ICON_THEME}
  fi
fi
export ICON_THEME

# Hyprland metadata (fast, run inline)
[ -f "${LIB_DIR}/hypr/wal/wal.hypr.sh" ] && source "${LIB_DIR}/hypr/wal/wal.hypr.sh"

# Chrome theming (non-critical, run in background)
[ -f "${LIB_DIR}/hypr/wal/wal.chrome.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.chrome.sh" &

# QT theming (run in background)
[ -f "${LIB_DIR}/hypr/wal/wal.qt.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.qt.sh" &

# dconf/kdeglobals (run in background)
[ -f "${LIB_DIR}/hypr/theme/dconf.set.sh" ] && bash "${LIB_DIR}/hypr/theme/dconf.set.sh" &

# Wait for parallel operations to complete
maybe_wait

post_updates() {
  # KDE/Dolphin settings
  if [ -n "${background}" ] && [ -n "${foreground}" ]; then
    kdeglobals="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"

    # Update icon theme (must be done before colors, uses ICON_THEME from dconf.set.sh)
    if [ -n "${ICON_THEME}" ]; then
      toml_write "$kdeglobals" "Icons" "Theme" "${ICON_THEME}"
    fi

    # Preserve terminal application setting
    if [ -n "${TERMINAL}" ]; then
      toml_write "$kdeglobals" "General" "TerminalApplication" "${TERMINAL}"
    fi

    # Helper to convert hex to R,G,B format
    hex_to_rgb() {
      local hex="${1#\#}"
      printf "%d,%d,%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
    }

    # In theme mode, use Kvantum theme colors instead of pywal wallpaper-extracted colors
    if [ "${enableWallDcol}" -eq 0 ]; then
      THEME_KVCONFIG="${HYPR_THEME_DIR}/kvantum/kvconfig.theme"
      if [ -f "$THEME_KVCONFIG" ]; then
        # Extract exact theme colors from theme's kvconfig.theme
        kv_window_bg=$(grep '^window\.color=' "$THEME_KVCONFIG" | cut -d= -f2)
        kv_text_fg=$(grep '^text\.color=' "$THEME_KVCONFIG" | cut -d= -f2)
        kv_highlight=$(grep '^highlight\.color=' "$THEME_KVCONFIG" | cut -d= -f2)

        # Override pywal colors with theme's exact colors
        [ -n "$kv_window_bg" ] && background="$kv_window_bg"
        [ -n "$kv_text_fg" ] && foreground="$kv_text_fg"
        [ -n "$kv_highlight" ] && color4="$kv_highlight" && color5="$kv_highlight"
      fi
    fi

    bg_rgb=$(hex_to_rgb "$background")
    fg_rgb=$(hex_to_rgb "$foreground")
    accent_rgb=$(hex_to_rgb "$color4")
    hover_rgb=$(hex_to_rgb "$color5")

    # View colors
    toml_write "$kdeglobals" "Colors:View" "BackgroundNormal" "$bg_rgb"
    toml_write "$kdeglobals" "Colors:View" "ForegroundNormal" "$fg_rgb"
    toml_write "$kdeglobals" "Colors:View" "DecorationFocus" "$accent_rgb"
    toml_write "$kdeglobals" "Colors:View" "DecorationHover" "$hover_rgb"

    # Selection colors (for selected items in Dolphin places panel)
    toml_write "$kdeglobals" "Colors:Selection" "BackgroundNormal" "$accent_rgb"
    toml_write "$kdeglobals" "Colors:Selection" "BackgroundAlternate" "$accent_rgb"
    toml_write "$kdeglobals" "Colors:Selection" "ForegroundNormal" "$fg_rgb"
    toml_write "$kdeglobals" "Colors:Selection" "ForegroundActive" "$fg_rgb"
    toml_write "$kdeglobals" "Colors:Selection" "DecorationFocus" "$accent_rgb"
    toml_write "$kdeglobals" "Colors:Selection" "DecorationHover" "$hover_rgb"

    # Window colors
    toml_write "$kdeglobals" "Colors:Window" "BackgroundNormal" "$bg_rgb"
    toml_write "$kdeglobals" "Colors:Window" "ForegroundNormal" "$fg_rgb"
  fi

  # Kvantum highlight colors now handled by wal.kvantum.sh in parallel

  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && {
    if ! hyprshell shaders --reload 2>&1 | grep -q "error"; then
      [[ "${LOG_LEVEL}" == "debug" ]] && print_log -sec "hyprshell" -stat "reload" "shaders"
    else
      print_log -sec "hyprshell" -warn "reload" "shader reload failed"
    fi
  }

  # Update waybar border-radius to match Hyprland rounding
  if [[ "${SKIP_WAYBAR_UPDATE}" -ne 1 ]]; then
    if [[ -x "${LIB_DIR}/hypr/waybar/waybar.py" ]]; then
      "${LIB_DIR}/hypr/waybar/waybar.py" --update-border-radius &>/dev/null
      print_log -sec "waybar" -stat "updated" "border-radius from theme"
    elif command -v hyprshell &>/dev/null; then
      hyprshell waybar --update-border-radius &>/dev/null
      print_log -sec "waybar" -stat "updated" "border-radius from theme"
    fi
  fi
}

if [[ "${ASYNC_APPS}" -eq 1 ]]; then
  post_updates &
else
  post_updates
fi

# Print colors if in terminal
[ -t 1 ] && [ -f "${LIB_DIR}/hypr/wal/wal.print.colors.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.print.colors.sh"

prev_mode=""
prev_colormode=""
if [[ -r "${STATE_FILE}" ]]; then
  prev_mode="$(awk -F= '/^mode=/{print $2; exit}' "${STATE_FILE}")"
  prev_colormode="$(awk -F= '/^colormode=/{print $2; exit}' "${STATE_FILE}")"
fi
mode_changed=false
colormode_changed=false
[[ -n "${prev_mode}" && "${prev_mode}" != "${dcol_mode}" ]] && mode_changed=true
[[ -n "${prev_colormode}" && "${prev_colormode}" != "${enableWallDcol}" ]] && colormode_changed=true

# State
{
  echo "${wal_cache_key:-${WALLPAPER_IMAGE:-theme}:${dcol_mode}}"
  echo "wallpaper=${WALLPAPER_IMAGE}"
  echo "mode=${dcol_mode}"
  echo "colormode=${enableWallDcol}"
  echo "backend=${PYWAL_BACKEND}"
} >"${STATE_FILE}"

# Notify
if [[ "${CACHE_ONLY}" -ne 1 ]] && [[ "${mode_changed}" == true || "${colormode_changed}" == true ]]; then
  command -v notify-send &>/dev/null \
    && notify-send "Theme Updated" "${dcol_mode} mode" -i preferences-desktop-theme -t 2000
fi

print_log -sec "pywal16" -stat "complete" "applied"
