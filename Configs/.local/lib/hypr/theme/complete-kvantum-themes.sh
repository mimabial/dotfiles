#!/usr/bin/env bash
# Complete incomplete Kvantum theme SVGs
# Uses a complete template and intelligently maps colors

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require system || exit 1

THEMES_DIR="${HYPR_CONFIG_HOME}/themes"
COMPLETE_TEMPLATE="Tokyo Night"
MIN_ELEMENTS=1000

sed_escape_pattern() {
    printf '%s' "$1" | sed 's/[.[\*^$()+?{|\\]/\\&/g; s/\//\\\//g'
}

kvantum_element_count() {
    local svg_file="$1"
    grep -oE 'id="[^"]*"' "${svg_file}" 2>/dev/null | grep -vE "linear|radial|grid|defs|svg" | wc -l
}

load_kvconfig_colors() {
    local kvconfig_file="$1"
    local map_name="$2"
    local -n map_ref="${map_name}"

    map_ref=()
    while IFS='=' read -r key value; do
        [[ -n "${key}" ]] || continue
        map_ref["${key}"]="${value}"
    done < <(grep -E "^[a-z.]+\.color=" "${kvconfig_file}")
}

build_direct_svg_color_map() {
    local template_map_name="$1"
    local theme_map_name="$2"
    local svg_map_name="$3"
    local -n template_map_ref="${template_map_name}"
    local -n theme_map_ref="${theme_map_name}"
    local -n svg_map_ref="${svg_map_name}"
    local key=""
    local template_color=""
    local theme_color=""

    svg_map_ref=()

    for key in "${!template_map_ref[@]}"; do
        template_color="${template_map_ref[$key]}"
        theme_color="${theme_map_ref[$key]:-}"
        [[ -n "${theme_color}" ]] || continue
        svg_map_ref["${template_color,,}"]="${theme_color}"
    done
}

resolve_fallback_svg_color() {
    local template_svg_color="$1"
    local theme_map_name="$2"
    local -n theme_map_ref="${theme_map_name}"

    case "${template_svg_color}" in
        "#7aa2f7"|"#2ac3de"|"#73daca"|"#b4f9f8"|"#cba6f7")
            printf '%s' "${theme_map_ref[highlight.color]:-}"
            ;;
        "#c0caf5")
            printf '%s' "${theme_map_ref[button.text.color]:-}"
            ;;
        "#1a1b26"|"#24283b")
            printf '%s' "${theme_map_ref[window.color]:-}"
            ;;
        *)
            printf ''
            ;;
    esac
}

extend_svg_color_map_with_fallbacks() {
    local template_svg="$1"
    local theme_map_name="$2"
    local svg_map_name="$3"
    local -n svg_map_ref="${svg_map_name}"
    local template_svg_color=""
    local target_color=""
    local -a template_svg_colors=()

    readarray -t template_svg_colors < <(grep -oE '#[0-9a-fA-F]{6}' "${template_svg}" | sort -u)

    for template_svg_color in "${template_svg_colors[@]}"; do
        [[ -n "${svg_map_ref[${template_svg_color,,}]:-}" ]] && continue

        target_color="$(resolve_fallback_svg_color "${template_svg_color}" "${theme_map_name}")"
        [[ -n "${target_color}" ]] || continue

        svg_map_ref["${template_svg_color,,}"]="${target_color}"
    done
}

render_svg_from_color_map() {
    local template_svg="$1"
    local output_svg="$2"
    local svg_map_name="$3"
    local -n svg_map_ref="${svg_map_name}"
    local source_color=""
    local target_color=""
    local source_color_pat=""
    local target_color_rep=""
    local -a sed_args=()

    for source_color in "${!svg_map_ref[@]}"; do
        target_color="${svg_map_ref[$source_color]}"
        source_color_pat="$(sed_escape_pattern "${source_color}")"
        target_color_rep="$(sed_escape_replacement "${target_color}")"
        sed_args+=(-e "s|${source_color_pat}|${target_color_rep}|gi")
    done

    ((${#sed_args[@]} > 0)) || return 1
    sed "${sed_args[@]}" "${template_svg}" > "${output_svg}"
}

complete_kvantum_theme() {
    local theme_dir="$1"
    local theme_name=""
    local kvantum_dir=""
    local kvantum_svg=""
    local kvconfig_file=""
    local template_kvconfig=""
    local template_svg=""
    local backup_file=""
    local element_count=0
    local new_element_count=0
    local theme_state=""
    declare -A template_colors
    declare -A theme_colors
    declare -A svg_color_map

    theme_name="$(basename "${theme_dir}")"
    kvantum_dir="${theme_dir}/kvantum"
    kvantum_svg="${kvantum_dir}/kvantum.theme"
    kvconfig_file="${kvantum_dir}/kvconfig.theme"

    [[ -d "${kvantum_dir}" ]] || return 0
    [[ -f "${kvconfig_file}" ]] || return 0

    if [[ -f "${kvantum_svg}" ]]; then
        element_count="$(kvantum_element_count "${kvantum_svg}")"
        if ((element_count >= MIN_ELEMENTS)); then
            echo "[${theme_name}] Already complete (${element_count} elements)"
            return 0
        fi
        theme_state="Incomplete"
    else
        theme_state="Missing"
    fi

    echo "[${theme_name}] ${theme_state} (${element_count} elements)"

    template_kvconfig="${THEMES_DIR}/${COMPLETE_TEMPLATE}/kvantum/kvconfig.theme"
    template_svg="${THEMES_DIR}/${COMPLETE_TEMPLATE}/kvantum/kvantum.theme"

    load_kvconfig_colors "${template_kvconfig}" template_colors
    load_kvconfig_colors "${kvconfig_file}" theme_colors
    build_direct_svg_color_map template_colors theme_colors svg_color_map
    extend_svg_color_map_with_fallbacks "${template_svg}" theme_colors svg_color_map

    ((${#svg_color_map[@]} > 0)) || return 0

    backup_file="${kvantum_svg}.incomplete-backup"
    mkdir -p "${kvantum_dir}"
    if [[ -f "${kvantum_svg}" && ! -f "${backup_file}" ]]; then
        cp "${kvantum_svg}" "${backup_file}"
        echo "  • Backed up original to kvantum.theme.incomplete-backup"
    fi

    render_svg_from_color_map "${template_svg}" "${kvantum_svg}" svg_color_map

    new_element_count="$(kvantum_element_count "${kvantum_svg}")"
    echo "  • Completed: ${element_count} -> ${new_element_count} elements"
    echo ""
}

resolve_theme_dir() {
    local raw_target="$1"

    if [[ -d "${raw_target}" ]]; then
        printf '%s\n' "${raw_target%/}"
        return 0
    fi

    if [[ -d "${THEMES_DIR}/${raw_target}" ]]; then
        printf '%s\n' "${THEMES_DIR}/${raw_target}"
        return 0
    fi

    printf 'WARN: theme not found: %s\n' "${raw_target}" >&2
    return 1
}

main() {
    local theme_dir=""
    local target=""
    local -a theme_dirs=()

    echo "Scanning for incomplete Kvantum themes..."
    echo ""

    if (($# > 0)); then
        for target in "$@"; do
            theme_dir="$(resolve_theme_dir "${target}")" || continue
            theme_dirs+=("${theme_dir}")
        done
    else
        for theme_dir in "${THEMES_DIR}"/*/; do
            theme_dirs+=("${theme_dir%/}")
        done
    fi

    for theme_dir in "${theme_dirs[@]}"; do
        complete_kvantum_theme "${theme_dir}"
    done

    echo ""
    echo "✓ Finished completing themes"
    echo "Run 'hyprshell theme.switch.sh <theme_name>' to apply changes"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
