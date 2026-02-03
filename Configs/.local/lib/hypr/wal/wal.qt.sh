#!/usr/bin/env bash
# QT theming for pywal16

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"
source "${LIB_DIR}/hypr/globalcontrol.sh"

# Source pywal16 colors
if ! source "${HOME}/.cache/wal/colors-shell.sh" 2>/dev/null; then
  echo "[qt] Error: pywal16 colors not found"
  exit 1
fi

confDir="${confDir:-$XDG_CONFIG_HOME}"

# Generate qt5ct colors.conf
mkdir -p "${confDir}/qt5ct/colors"
cat >"${confDir}/qt5ct/colors/pywal16.conf" <<EOF
[ColorScheme]
active_colors=${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color5}, ${color15}, ${color15}, ${color15}, ${color7}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}
disabled_colors=${color8}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color5}, ${color15}, ${color15}, ${color15}, ${color7}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}
inactive_colors=${color6}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color5}, ${color15}, ${color15}, ${color15}, ${color7}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}, ${color15}
EOF

# Sync qt5ct to qt6ct
mkdir -p "${confDir}/qt6ct/colors"
cp "${confDir}/qt5ct/colors/pywal16.conf" "${confDir}/qt6ct/colors/pywal16.conf"

echo "[qt] Generated pywal16 color scheme"
