#!/usr/bin/env bash

set -e
baseDir="$(dirname "$(realpath "$0")")"
mapfile -t flats < <(sed 's/#.*//; s/[[:space:]]//g; /^$/d' "${baseDir}/custom_flat.lst")
((${#flats[@]})) || exit 0

flatpak install --user -y flathub "${flats[@]}"
flatpak remove --user -y --unused

gtkTheme="$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")"
gtkIcon="$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")"
for path in "$HOME/.themes" "$HOME/.icons" "$HOME/.local/share/themes" "$HOME/.local/share/icons"; do
    flatpak override --user --filesystem="$path"
done
flatpak override --user --env="GTK_THEME=${gtkTheme}" --env="ICON_THEME=${gtkIcon}"
