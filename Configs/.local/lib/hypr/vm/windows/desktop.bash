windows_prepare_directories() {
  mkdir -p "$WINDOWS_DATA_DIR" "${WINDOWS_CONFIG_DIR}" "$WINDOWS_ICON_DIR"
}

windows_copy_launcher_icon() {
  local source_icon="${XDG_DATA_HOME}/icons/windows.png"
  local target_icon="$WINDOWS_ICON_DIR/windows.png"

  [ -f "$source_icon" ] || return 0
  cp "$source_icon" "$target_icon"
}

windows_write_desktop_entry() {
  cat > "$WINDOWS_DESKTOP_FILE" <<EOF2
[Desktop Entry]
Name=Windows
Comment=Start Windows VM via Docker and connect with RDP
Exec=hyprshell vm/windows.sh launch
Icon=$WINDOWS_ICON_DIR/windows.png
Terminal=false
Type=Application
Categories=System;Virtualization;
EOF2
}

windows_install_desktop_assets() {
  windows_copy_launcher_icon
  windows_write_desktop_entry
}
