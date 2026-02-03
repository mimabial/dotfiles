#!/usr/bin/env bash
# Complete incomplete Kvantum theme SVGs
# Uses a complete template and intelligently maps colors

set -euo pipefail

THEMES_DIR="${HOME}/.config/hypr/themes"
COMPLETE_TEMPLATE="Tokyo Night"  # Use Tokyo Night as the complete template
MIN_ELEMENTS=1000  # Themes with fewer elements are considered incomplete

echo "Scanning for incomplete Kvantum themes..."
echo ""

for theme_dir in "${THEMES_DIR}"/*/; do
    theme_name=$(basename "${theme_dir}")
    kvantum_svg="${theme_dir}/kvantum/kvantum.theme"
    kvconfig_file="${theme_dir}/kvantum/kvconfig.theme"

    # Skip if no kvantum directory or files
    [ ! -f "${kvantum_svg}" ] && continue
    [ ! -f "${kvconfig_file}" ] && continue

    # Count elements in SVG
    element_count=$(grep -oE 'id="[^"]*"' "${kvantum_svg}" 2>/dev/null | grep -vE "linear|radial|grid|defs|svg" | wc -l)

    if [ "${element_count}" -lt "${MIN_ELEMENTS}" ]; then
        echo "[$theme_name] Incomplete (${element_count} elements)"

        # Generate color mapping
        template_kvconfig="${THEMES_DIR}/${COMPLETE_TEMPLATE}/kvantum/kvconfig.theme"
        template_svg="${THEMES_DIR}/${COMPLETE_TEMPLATE}/kvantum/kvantum.theme"

        # Build color mapping from template to target theme
        declare -A template_colors
        declare -A theme_colors

        while IFS='=' read -r key value; do
            [ -z "${key}" ] && continue
            template_colors["${key}"]="${value}"
        done < <(grep -E "^[a-z.]+\.color=" "${template_kvconfig}")

        while IFS='=' read -r key value; do
            [ -z "${key}" ] && continue
            theme_colors["${key}"]="${value}"
        done < <(grep -E "^[a-z.]+\.color=" "${kvconfig_file}")

        # Build sed replacement args
        SED_ARGS=()
        for key in "${!template_colors[@]}"; do
            template_color="${template_colors[$key]}"
            theme_color="${theme_colors[$key]:-}"

            if [ -n "${theme_color}" ]; then
                SED_ARGS+=(-e "s/${template_color}/${theme_color}/gi")
            fi
        done

        # Extract all unique hex colors from template SVG
        # and try to map them intelligently
        readarray -t template_svg_colors < <(grep -oE '#[0-9a-fA-F]{6}' "${template_svg}" | sort -u)

        for template_svg_color in "${template_svg_colors[@]}"; do
            # Skip if already in replacement args
            already_mapped=false
            for arg in "${SED_ARGS[@]}"; do
                if [[ "${arg}" =~ ${template_svg_color} ]]; then
                    already_mapped=true
                    break
                fi
            done

            if ! $already_mapped; then
                # Try to map based on similarity to kvconfig colors
                # For now, map accent/highlight colors to theme's highlight
                # and neutrals to theme's similar neutrals
                case "${template_svg_color}" in
                    "#7aa2f7"|"#2ac3de"|"#73daca"|"#b4f9f8"|"#cba6f7")
                        # Template accent colors -> theme highlight
                        target_color="${theme_colors[highlight.color]:-}"
                        [ -n "${target_color}" ] && SED_ARGS+=(-e "s/${template_svg_color}/${target_color}/gi")
                        ;;
                    "#c0caf5")
                        # Light foreground -> theme button text
                        target_color="${theme_colors[button.text.color]:-}"
                        [ -n "${target_color}" ] && SED_ARGS+=(-e "s/${template_svg_color}/${target_color}/gi")
                        ;;
                    "#1a1b26"|"#24283b")
                        # Deep background -> theme window
                        target_color="${theme_colors[window.color]:-}"
                        [ -n "${target_color}" ] && SED_ARGS+=(-e "s/${template_svg_color}/${target_color}/gi")
                        ;;
                esac
            fi
        done

        if [ ${#SED_ARGS[@]} -gt 0 ]; then
            # Backup original
            backup_file="${kvantum_svg}.incomplete-backup"
            if [ ! -f "${backup_file}" ]; then
                cp "${kvantum_svg}" "${backup_file}"
                echo "  • Backed up original to kvantum.theme.incomplete-backup"
            fi

            # Create completed SVG
            sed "${SED_ARGS[@]}" "${template_svg}" > "${kvantum_svg}"

            # Verify
            new_element_count=$(grep -oE 'id="[^"]*"' "${kvantum_svg}" 2>/dev/null | grep -vE "linear|radial|grid|defs|svg" | wc -l)
            echo "  • Completed: ${element_count} -> ${new_element_count} elements"
            echo ""
        fi

        unset template_colors theme_colors SED_ARGS
    else
        echo "[$theme_name] Already complete (${element_count} elements)"
    fi
done

echo ""
echo "✓ Finished completing themes"
echo "Run 'hyprshell theme.switch.sh <theme_name>' to apply changes"
