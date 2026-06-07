#!/bin/bash
# ==============================================================================
# Script Name: install_oldschool_fonts.sh for all LinuxOS's
# Created by: Blacky, Blackcrack (blackysgate.de) & Nova (ChatGPT.com)
# Description: Installs Oldschool PC Fonts to standard system font directories.
#              Automatically detects major Linux distro font paths.
#              Uses optional 'pv' for progress bar during extraction.
# Download URL: https://int10h.org/oldschool-pc-fonts/download/oldschool_pc_font_pack_v2.2_linux.zip
#  p.s. sometimes changed the download-url :\
# ==============================================================================

URL="https://int10h.org/oldschool-pc-fonts/download/oldschool_pc_font_pack_v2.2_linux.zip"

# ===================== Functions =====================

# Function: check_root
# Purpose: Ensures the script is run with root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Please run as root or using sudo."
        exit 1
    fi
}

# Function: get_script_dir
# Purpose: Determines the directory where the script is located
get_script_dir() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# Function: extract_filename
# Purpose: Extracts the filename from the URL for local storage
extract_filename() {
    LOCAL_ZIP="${URL##*/}"   # everything after the last slash
    FULL_ZIP_PATH="$SCRIPT_DIR/$LOCAL_ZIP"
}

# Function: detect_font_dir
# Purpose: Detects a standard system font directory and prepares target subdir
detect_font_dir() {
    STANDARD_FONT_DIRS=(
        "/usr/share/fonts"
        "/usr/local/share/fonts"
        "/usr/X11R6/lib/X11/fonts"
        "/usr/lib/X11/fonts"
    )
    TARGET_DIR=""
    for dir in "${STANDARD_FONT_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            TARGET_DIR="$dir/oldschool_pc_fonts"
            break
        fi
    done
    # fallback if none exist
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="/usr/share/fonts/oldschool_pc_fonts"
    fi
    mkdir -p "$TARGET_DIR"
}

# Function: check_dependencies
# Purpose: Ensures required commands are available before proceeding
check_dependencies() {
    for cmd in unzip fc-cache wget; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
}

# Function: download_zip
# Purpose: Downloads the zip file if it doesn't exist locally
download_zip() {
    if [ -f "$FULL_ZIP_PATH" ]; then
        echo "Found local zip: $LOCAL_ZIP. Skipping download."
    else
        echo "Local file not found. Downloading from $URL ..."
        wget -q --show-progress -O "$FULL_ZIP_PATH" "$URL"
        if [ $? -ne 0 ]; then
            echo "Error: Download failed. Check your internet connection."
            [ -f "$FULL_ZIP_PATH" ] && rm "$FULL_ZIP_PATH"
            exit 1
        fi
    fi
}

# Function: extract_fonts
# Purpose: Extracts fonts into the target directory.
#          Uses 'pv' if available for a progress bar, otherwise normal unzip
extract_fonts() {
    echo "Extracting fonts to $TARGET_DIR ..."
    if command -v pv &> /dev/null; then
        FILE_SIZE=$(stat -c%s "$FULL_ZIP_PATH")
        pv -s "$FILE_SIZE" "$FULL_ZIP_PATH" | unzip -q -o -d "$TARGET_DIR" -
    else
        unzip -q -o "$FULL_ZIP_PATH" -d "$TARGET_DIR"
    fi
}

# Function: update_font_cache
# Purpose: Refreshes the system font cache to make the fonts immediately available
update_font_cache() {
    echo "Refreshing system font cache..."
    fc-cache -f
}

# Function: print_summary
# Purpose: Prints a clear installation summary for the user
print_summary() {
    echo "--------------------------------------------------------"
    echo "Installation Successful!"
    echo "Fonts installed in: $TARGET_DIR"
    echo "Zip file kept in: $FULL_ZIP_PATH"
    echo "--------------------------------------------------------"
}

# ===================== Main Script =====================
# Sequential calls to each function; easy to follow and learn

check_root           # Ensure we have root privileges
get_script_dir       # Find the directory of this script
extract_filename     # Get the local zip filename from URL
detect_font_dir      # Detect system font directory and create subfolder
check_dependencies   # Ensure required commands exist
download_zip         # Download fonts if not already present
extract_fonts        # Extract fonts (with optional progress bar)
update_font_cache    # Update the system font cache
print_summary        # Print installation summary for the user
