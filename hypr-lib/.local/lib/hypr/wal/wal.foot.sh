#!/usr/bin/env bash
# Foot terminal pywal16 integration
# Updates foot terminal colors from pywal

scrDir=$(dirname "$(realpath "$0")")
source "${scrDir}/../globalcontrol.sh"

# Paths
FOOT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
FOOT_TEMPLATE="${FOOT_CONFIG}.template"
PYWAL_COLORS="${HOME}/.cache/wal/colors-foot.ini"

# Check if pywal colors exist
if [[ ! -f "${PYWAL_COLORS}" ]]; then
    echo "Error: Pywal colors not found at ${PYWAL_COLORS}"
    exit 1
fi

# Check if foot config exists
if [[ ! -f "${FOOT_CONFIG}" ]]; then
    echo "Error: Foot config not found at ${FOOT_CONFIG}"
    exit 1
fi

# Create template backup if it doesn't exist
if [[ ! -f "${FOOT_TEMPLATE}" ]]; then
    # Remove any existing [colors] section from config to create clean template
    awk '
        /^\[colors\]/ { skip=1; next }
        /^\[/ && skip { skip=0 }
        !skip { print }
    ' "${FOOT_CONFIG}" > "${FOOT_TEMPLATE}"
fi

# Merge template with pywal colors
{
    cat "${FOOT_TEMPLATE}"
    echo ""
    echo "# ============================================================================"
    echo "# Pywal16 Colors (auto-generated)"
    echo "# ============================================================================"
    cat "${PYWAL_COLORS}"
} > "${FOOT_CONFIG}"

echo "Foot terminal colors updated from pywal"
