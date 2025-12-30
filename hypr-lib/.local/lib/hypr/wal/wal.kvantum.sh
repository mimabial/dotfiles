#!/usr/bin/env bash
# wal.kvantum.sh - Kvantum theme generation with pywal colors
# Runs in parallel with other app theming scripts

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
hashFile="${XDG_RUNTIME_DIR:-/tmp}/wal-kvantum-hash"
PYWAL_KVANTUM_DIR="${HOME}/.config/Kvantum/pywal16"

# Get required variables from environment or state
[ -f "$HYPR_STATE_HOME/config" ] && source "$HYPR_STATE_HOME/config"
enableWallDcol="${enableWallDcol:-1}"

# Determine theme directory
if [ -z "${HYPR_THEME_DIR}" ] && [ -n "${HYPR_THEME}" ]; then
    HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
fi

THEME_KVANTUM_DIR="${HYPR_THEME_DIR}/kvantum"

# Exit early if no kvantum theme exists
if [ ! -d "${THEME_KVANTUM_DIR}" ]; then
    exit 0
fi

# Change detection: hash inputs (theme kvantum files + pywal colors + mode)
input_files=(
    "${THEME_KVANTUM_DIR}/kvconfig.theme"
    "${THEME_KVANTUM_DIR}/kvantum.theme"
    "${THEME_KVANTUM_DIR}/colors.map"
)
input_hash=$(cat "${input_files[@]}" "${WAL_CACHE}/colors.sh" 2>/dev/null | md5sum | cut -d' ' -f1)
combined_hash="${input_hash}-${enableWallDcol}"

if [[ -f "$hashFile" && "$(cat "$hashFile" 2>/dev/null)" == "$combined_hash" ]]; then
    exit 0  # Nothing changed
fi

mkdir -p "${PYWAL_KVANTUM_DIR}"

# Copy theme's kvconfig
if [ -f "${THEME_KVANTUM_DIR}/kvconfig.theme" ]; then
    cp -f "${THEME_KVANTUM_DIR}/kvconfig.theme" "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
fi

# Copy theme's SVG
if [ -f "${THEME_KVANTUM_DIR}/kvantum.theme" ]; then
    cp -f "${THEME_KVANTUM_DIR}/kvantum.theme" "${PYWAL_KVANTUM_DIR}/pywal16.svg"
fi

# Source pywal colors
if [ -f "${WAL_CACHE}/colors.sh" ]; then
    source "${WAL_CACHE}/colors.sh"
fi

# In wallpaper mode, replace colors using colors.map
if [ "${enableWallDcol}" -ne 0 ]; then
    COLOR_MAP="${THEME_KVANTUM_DIR}/colors.map"

    if [ -f "${COLOR_MAP}" ]; then
        # Build sed command from colors.map
        SED_ARGS=()
        while IFS='=' read -r hex_color pywal_var || [ -n "${hex_color}" ]; do
            # Skip comments and empty lines
            [[ "${hex_color}" =~ ^#.*$ && ! "${hex_color}" =~ ^#[0-9A-Fa-f]{6}$ ]] && continue
            [[ -z "${hex_color}" ]] && continue

            # Get the pywal color value
            pywal_value="${!pywal_var}"
            [ -z "${pywal_value}" ] && continue

            # Add case-insensitive replacement
            SED_ARGS+=(-e "s/${hex_color}/${pywal_value}/gi")
        done <"${COLOR_MAP}"

        # Apply replacements to kvconfig
        if [ -f "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig" ] && [ ${#SED_ARGS[@]} -gt 0 ]; then
            sed -i "${SED_ARGS[@]}" "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
        fi

        # Apply replacements to SVG
        if [ -f "${PYWAL_KVANTUM_DIR}/pywal16.svg" ] && [ ${#SED_ARGS[@]} -gt 0 ]; then
            sed -i "${SED_ARGS[@]}" "${PYWAL_KVANTUM_DIR}/pywal16.svg"
        fi

        # Fix selection colors for various SVG elements
        if [ -f "${PYWAL_KVANTUM_DIR}/pywal16.svg" ]; then
            # Replace fill colors within itemview-toggled and itemview-pressed groups
            sed -i -E '
                /id="itemview-(toggled|pressed)/,/<\/g>|<\/(rect|path)>/ {
                    s/fill:#[0-9a-fA-F]{6}/fill:'"${color4}"'/g
                }
            ' "${PYWAL_KVANTUM_DIR}/pywal16.svg"

            # Fix toolbar button toggled/pressed colors
            sed -i -E '
                /id="tbutton-(toggled|pressed)/,/<\/g>|<\/(rect|path)>/ {
                    s/fill:#[0-9a-fA-F]{6}/fill:'"${color4}"'/g
                }
            ' "${PYWAL_KVANTUM_DIR}/pywal16.svg"

            # Fix regular button toggled/pressed colors
            sed -i -E '
                /id="button-(toggled|pressed)(-|")/,/<\/g>|<\/(rect|path)>/ {
                    s/fill:#[0-9a-fA-F]{6}/fill:'"${color4}"'/g
                }
            ' "${PYWAL_KVANTUM_DIR}/pywal16.svg"
        fi
    fi
fi

# Update highlight colors in kvconfig
kvconfig="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
if [ -f "$kvconfig" ] && [ -n "${color4}" ]; then
    # In theme mode, extract colors from the theme's kvconfig
    if [ "${enableWallDcol}" -eq 0 ]; then
        THEME_KVCONFIG="${THEME_KVANTUM_DIR}/kvconfig.theme"
        if [ -f "$THEME_KVCONFIG" ]; then
            kv_highlight=$(grep '^highlight\.color=' "$THEME_KVCONFIG" | cut -d= -f2)
            kv_text=$(grep '^text\.color=' "$THEME_KVCONFIG" | cut -d= -f2)
            [ -n "$kv_highlight" ] && color4="$kv_highlight"
            [ -n "$kv_text" ] && foreground="$kv_text"
        fi
    fi

    # Update highlight colors
    sed -i "s/^highlight\.color=.*/highlight.color=${color4}/" "$kvconfig"
    sed -i "s/^inactive\.highlight\.color=.*/inactive.highlight.color=${color4}/" "$kvconfig"
    [ -n "${foreground}" ] && sed -i "s/^highlight\.text\.color=.*/highlight.text.color=${foreground}/" "$kvconfig"

    # Reduce menu opacity for better visibility
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file "$kvconfig" --group '%General' --key 'reduce_menu_opacity' 0 2>/dev/null
    fi
fi

# Save hash for next run
echo "$combined_hash" > "$hashFile"
