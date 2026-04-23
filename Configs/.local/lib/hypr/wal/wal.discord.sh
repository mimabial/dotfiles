#!/usr/bin/env bash
# pywal16.discord.sh - Copy generated Discord CSS to client locations

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/core/hash-cache.sh" || exit 1

discord_css="${XDG_CACHE_HOME:-$HOME/.cache}/wal/discord.css"
hash_file="$(hypr_hash_cache_runtime_file "wal-discord-hash")" || exit 1

# Exit if source file doesn't exist
[ ! -f "${discord_css}" ] && exit 0

# Change detection: skip if CSS unchanged
input_hash="$(hypr_hash_cache_digest_files "${discord_css}")"
if hypr_hash_cache_is_current "${hash_file}" "${input_hash}"; then
  exit 0
fi

# List of Discord client CSS locations
declare -a clients=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/Vencord/settings/quickCss.css"
  "${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/settings/quickCss.css"
  "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/settings/quickCss.css"
  "${XDG_CONFIG_HOME:-$HOME/.config}/WebCord/Themes/theme.css"
  "$HOME/.var/app/io.github.spacingbat3.webcord/config/WebCord/Themes/theme.css"
  "$HOME/.var/app/xyz.armcord.ArmCord/config/ArmCord/themes/theme.css"
)

for client in "${clients[@]}"; do
  if [[ -d $(dirname "$client") ]]; then
    cp "$discord_css" "$client"
  fi
done

# Save hash for next run
hypr_hash_cache_store "${hash_file}" "${input_hash}"
