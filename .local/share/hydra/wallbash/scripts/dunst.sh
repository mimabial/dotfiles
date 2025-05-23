#!/usr/bin/env bash

# shellcheck source=$HOME/.local/bin/hydra-shell
# shellcheck disable=SC1091
if ! source "$(which hydra-shell)"; then
  echo "[wallbash] code :: Error: hydra-shell not found."
  echo "[wallbash] code :: Is Hydra installed?"
  exit 1
fi

confDir="${confDir:-$HOME/.config}"
gtkIcon="${gtkIcon:-Tela-circle-dracula}"
iconsDir="${iconsDir:-$XDG_DATA_HOME/icons}"
cacheDir="${cacheDir:-$XDG_CACHE_HOME/hydra}"
WALLBASH_SCRIPTS="${WALLBASH_SCRIPTS:-$hydraConfDir/wallbash/scripts}"
hypr_border=10
dunstDir="${confDir}/dunst"
allIcons=$(find "${XDG_DATA_HOME:-$HOME/.local/share}/icons" -mindepth 1 -maxdepth 2 -name "icon-theme.cache" -print0 | xargs -0 -n1 dirname | xargs -n1 basename | paste -sd, -)

# Set font name
font_name=${NOTIFICATION_FONT}
font_name=${font_name:-$(get_hyprConf "NOTIFICATION_FONT")}
font_name=${font_name:-$(get_hyprConf "FONT")}

# Set font size
font_size=${NOTIFICATION_FONT_SIZE}
font_size=${font_size:-$(get_hyprConf "FONT_SIZE")}

cat <<WARN >"${dunstDir}/dunstrc"
# WARNING: This file is auto-generated by '${WALLBASH_SCRIPTS}/dunst.sh'.
# DO NOT edit manually.
# For user configuration edit '${confDir}/dunst/dunst.conf' then run 'hydra-shell wallbash dunst' to apply changes.
# Updated dunst configuration: https://github.com/Hydra-Project/Hydra/blob/master/Configs/.config/dunst/dunst.conf

# Hydra specific section // To override the default configuration edit '${cacheDir}/wallbash/dunst.conf'
# ------------------------------------------------------------------------------
[global]
corner_radius = ${hypr_border}
icon_corner_radius = ${hypr_border}
dmenu = $(which rofi) -config notification -dmenu -p dunst:
icon_theme = "${gtkIcon},${allIcons}"


# [Type-1]
# appname = "t1"
# format = "<b>%s</b>"

# [Type-2]
# appname = "Hydra Notify"
# format = "<span size="250%">%s</span>\n%b"

[Type-1]
appname = "Hydra Alert"
format = "<b>%s</b>"

[Type-2]
appname = "Hydra Notify"
format = "<span size="250%">%s</span>\n%b"



[urgency_critical]
background = "#f5e0dc"
foreground = "#1e1e2e"
frame_color = "#f38ba8"
icon = "${iconsDir}/Wallbash-Icon/critical.svg"
timeout = 0

# ------------------------------------------------------------------------------

WARN

# For Clarity We added a warning and remove comments and empty lines for the auto-generated file
grep -v '^\s*#' "${dunstDir}/dunst.conf" | grep -v '^\s*$' | envsubst >>"${dunstDir}/dunstrc"

cat <<MANDATORY >>"${dunstDir}/dunstrc"
# Hydra Mandatory section // Non overridable // please open a request in https://github.com/Hydra-Project/Hydra
# ------------------------------------------------------------------------------
[global]

# to change font and size, set the following variables in ~/.config/hydra/config.toml
# [notification]
# font = "mononoki Nerd Font"
# font_size = 10
font = ${font_name:-mononoki Nerd Font} ${font_size:-8}

dmenu = $(which rofi) -config notification -dmenu -p dunst:


# Wallbash section
# ------------------------------------------------------------------------------

MANDATORY

mkdir -p "${cacheDir}/wallbash"
envsubst <"${cacheDir}/wallbash/dunst.conf" >>"${dunstDir}/dunstrc"
killall dunst
dunst &
