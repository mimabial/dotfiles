#!/usr/bin/env bash
# pywal16.discord.sh - Copy generated Discord CSS to client locations

cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}"
confDir="${XDG_CONFIG_HOME:-$HOME/.config}"
discord_css="${cacheDir}/wal/discord.css"

# Exit if source file doesn't exist
[ ! -f "${discord_css}" ] && exit 0

# List of Discord client CSS locations
declare -a clients=(
  "${confDir}/Vencord/settings/quickCss.css"
  "${confDir}/vesktop/settings/quickCss.css"
  "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/settings/quickCss.css"
  "${confDir}/WebCord/Themes/theme.css"
  "$HOME/.var/app/io.github.spacingbat3.webcord/config/WebCord/Themes/theme.css"
  "$HOME/.var/app/xyz.armcord.ArmCord/config/ArmCord/themes/theme.css"
)

for client in "${clients[@]}"; do
  if [[ -d $(dirname "$client") ]]; then
    cp "$discord_css" "$client"
  fi
done
