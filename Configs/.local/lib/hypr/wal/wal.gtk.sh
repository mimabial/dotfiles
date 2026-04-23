#!/usr/bin/env bash
# pywal16.gtk.sh - Create Pywal16-Gtk theme with dynamic border-radius

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/core/hash-cache.sh" || exit 1

THEMES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
GTK_THEME_DIR="${THEMES_DIR}/Pywal16-Gtk"
GTK_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
HASH_FILE="$(hypr_hash_cache_runtime_file "wal-gtk-hash")" || exit 1
GTK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

gtk3_source="${GTK_CACHE_DIR}/colors-gtk3.css"
gtk4_source="${GTK_CACHE_DIR}/colors-gtk4.css"
gtk2_source="${GTK_CACHE_DIR}/colors-gtk2.rc"

get_hypr_border() {
  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r '.int // 8'
  else
    printf '8\n'
  fi
}

input_hash() {
  hypr_hash_cache_digest_files "${gtk3_source}" "${gtk4_source}"
}

theme_inputs_changed() {
  local combined_hash="$1"
  ! hypr_hash_cache_is_current "${HASH_FILE}" "${combined_hash}"
}

scale_radius() {
  local input_file="$1"
  local output_file="$2"

  awk -v r="$hypr_border" '
  BEGIN {
      r2 = int(r * 2)
      r7_3 = int(r * 7 / 3)
      r5_3 = int(r * 5 / 3)
      r3_2 = int(r + r / 2)
      r4_3 = int(r * 4 / 3)
      r7_6 = int(r * 7 / 6)
      r5_6 = int(r * 5 / 6)
      r2_3 = int(r * 2 / 3)
      r1_2 = int(r / 2)
      r1_3 = int(r / 3)
      r1_6 = int(r / 6)
  }
  {
      gsub(/border-radius: 12px 12px 12px 12px;/, "border-radius: " r2 "px " r2 "px " r2 "px " r2 "px;")
      gsub(/border-radius: 12px 12px 0 0;/, "border-radius: " r2 "px " r2 "px 0 0;")
      gsub(/border-radius: 0 0 12px 12px;/, "border-radius: 0 0 " r2 "px " r2 "px;")
      gsub(/border-radius: 0 12px 12px 0;/, "border-radius: 0 " r2 "px " r2 "px 0;")
      gsub(/border-radius: 0 0 12px 0;/, "border-radius: 0 0 " r2 "px 0;")
      gsub(/border-radius: 0 0 0 12px;/, "border-radius: 0 0 0 " r2 "px;")
      gsub(/border-radius: 6px 6px 6px 6px;/, "border-radius: " r "px " r "px " r "px " r "px;")
      gsub(/border-radius: 6px 6px 0 0;/, "border-radius: " r "px " r "px 0 0;")
      gsub(/border-radius: 6px 0 0 6px;/, "border-radius: " r "px 0 0 " r "px;")
      gsub(/border-radius: 0 6px 6px 0;/, "border-radius: 0 " r "px " r "px 0;")
      gsub(/border-radius: 0 0 6px 6px;/, "border-radius: 0 0 " r "px " r "px;")
      gsub(/border-radius: 0 0 6px 0;/, "border-radius: 0 0 " r "px 0;")
      gsub(/border-radius: 0 0 0 6px;/, "border-radius: 0 0 0 " r "px;")

      $0 = gensub(/([a-z-]*radius:) 14px;/, "\\1 " r7_3 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 12px;/, "\\1 " r2 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 10px;/, "\\1 " r5_3 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 9px;/, "\\1 " r3_2 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 8px;/, "\\1 " r4_3 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 7px;/, "\\1 " r7_6 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 6px;/, "\\1 " r "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 5px;/, "\\1 " r5_6 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 4px;/, "\\1 " r2_3 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 3px;/, "\\1 " r1_2 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 2px;/, "\\1 " r1_3 "px;", "g")
      $0 = gensub(/([a-z-]*radius:) 1px;/, "\\1 " r1_6 "px;", "g")
      print
  }' "$input_file" >"$output_file"
}

write_scaled_css() {
  local source_file="$1"
  local output_dir="$2"
  local tmp_file="${output_dir}/gtk.css.tmp"

  [[ -f "$source_file" ]] || return 0
  mkdir -p "$output_dir"

  {
    echo "/* Hyprland border radius: ${hypr_border}px */"
    echo
    cat "$source_file"
  } >"$tmp_file"

  scale_radius "$tmp_file" "${output_dir}/gtk.css"
  rm -f "$tmp_file"
  ln -sf gtk.css "${output_dir}/gtk-dark.css"
}

write_gtk2_theme() {
  [[ -f "$gtk2_source" ]] || return 0
  mkdir -p "${GTK_THEME_DIR}/gtk-2.0"
  cp "$gtk2_source" "${GTK_THEME_DIR}/gtk-2.0/gtkrc"
}

ensure_index_theme() {
  [[ -f "${GTK_THEME_DIR}/index.theme" ]] && return 0

  cat >"${GTK_THEME_DIR}/index.theme" <<EOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Pywal16-Gtk
Comment=Dynamic GTK theme generated from pywal16 colors
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Pywal16-Gtk
MetacityTheme=Pywal16-Gtk
IconTheme=Adwaita
CursorTheme=Adwaita
ButtonLayout=close,minimize,maximize:menu
EOF
}

notify_xsettingsd() {
  local conf="${GTK_CONFIG_DIR}/xsettingsd/xsettingsd.conf"

  command -v xsettingsd >/dev/null 2>&1 || return 0
  hypr_user_pgrep -x xsettingsd >/dev/null || return 0

  if [[ -f "$conf" ]]; then
    sed -i 's/^Net\/ThemeName ".*"$/Net\/ThemeName "Pywal16-Gtk"/' "$conf"
  fi

  hypr_user_pkill -HUP -x xsettingsd 2>/dev/null
}

notify_gtk_settings() {
  local gtk_config=""

  for gtk_config in "${GTK_CONFIG_DIR}/gtk-3.0/settings.ini" "${GTK_CONFIG_DIR}/gtk-4.0/settings.ini"; do
    [[ -f "$gtk_config" ]] || continue
    sed -i 's/^gtk-theme-name=.*/gtk-theme-name=Pywal16-Gtk/' "$gtk_config"
  done
}

write_theme() {
  mkdir -p "${GTK_THEME_DIR}/gtk-3.0" "${GTK_THEME_DIR}/gtk-4.0"
  write_scaled_css "$gtk3_source" "${GTK_THEME_DIR}/gtk-3.0"
  write_scaled_css "$gtk4_source" "${GTK_THEME_DIR}/gtk-4.0"
  write_gtk2_theme
  ensure_index_theme
}

hypr_border="$(get_hypr_border)"
combined_hash="$(input_hash)-${hypr_border}"
theme_inputs_changed "$combined_hash" || exit 0

write_theme
hypr_hash_cache_store "${HASH_FILE}" "${combined_hash}"
notify_xsettingsd
notify_gtk_settings
