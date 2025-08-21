#!/usr/bin/env bash

# Enable debug mode with: export DEBUG_THEME_PATCH=true
DEBUG_MODE="${DEBUG_THEME_PATCH:-false}"

# Debug logging function
debug_log() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "[DEBUG $(date '+%H:%M:%S')] $*" >&2
    fi
}

# Error logging function
error_log() {
    echo "[ERROR $(date '+%H:%M:%S')] $*" >&2
}

# Enhanced trap for debugging
trap 'error_log "Script failed at line $LINENO with exit code $?. Last command: $BASH_COMMAND"' ERR

debug_log "=== THEME PATCH DEBUG SESSION STARTED ==="
debug_log "Arguments: $*"
debug_log "Working directory: $(pwd)"
debug_log "User: $(whoami)"
debug_log "Shell: $SHELL"

script_dir=$(dirname "$(realpath "$0")")
debug_log "Script directory: $script_dir"

# Check if globalcontrol.sh exists
if [[ ! -f "${script_dir}/globalcontrol.sh" ]]; then
    error_log "globalcontrol.sh not found at: ${script_dir}/globalcontrol.sh"
    debug_log "Contents of script directory:"
    ls -la "$script_dir" >&2
    exit 1
fi

debug_log "Sourcing globalcontrol.sh from: ${script_dir}/globalcontrol.sh"
# shellcheck disable=SC1091
if ! source "${script_dir}/globalcontrol.sh"; then
    error_log "Failed to source globalcontrol.sh"
    exit 1
fi
debug_log "Successfully sourced globalcontrol.sh"

export VERBOSE="${4}"
debug_log "VERBOSE set to: $VERBOSE"
set +e

# error function
ask_help() {
    cat <<HELP
Usage:
    $(print_log "$0 " -y "Theme-Name " -c "/Path/to/Configs")
    $(print_log "$0 " -y "Theme-Name " -c "https://github.com/User/Repository")
    $(print_log "$0 " -y "Theme-Name " -c "https://github.com/User/Repository/tree/branch")

Debug Mode:
    export DEBUG_THEME_PATCH=true        Enable detailed debugging output

Envs:
    'export FULL_THEME_UPDATE=true'       Overwrites the archived files (useful for updates and changes in archives)

Supported Archive Format:
    | File prefix        | Hyprland variable | Target Directory                |
    | ---------------    | ----------------- | --------------------------------|
    | Gtk_              | \$GTK_THEME        | \$HOME/.local/share/themes     |
    | Icon_              | \$ICON_THEME       | \$HOME/.local/share/icons      |
    | Cursor_            | \$CURSOR_THEME     | \$HOME/.local/share/icons      |
    | Sddm_              | \$SDDM_THEME       | /usr/share/sddm/themes         |
    | Font_              | \$FONT             | \$HOME/.local/share/fonts      |
    | Document-Font_     | \$DOCUMENT_FONT    | \$HOME/.local/share/fonts      |
    | Monospace-Font_    | \$MONOSPACE_FONT   | \$HOME/.local/share/fonts      |
    | Notification-Font_ | \$NOTIFICATION_FONT | \$HOME/.local/share/fonts  |
    | Bar-Font_          | \$BAR_FONT         | \$HOME/.local/share/fonts      |
    | Menu-Font_         | \$MENU_FONT        | \$HOME/.local/share/fonts      |

Note:
    Target directories without enough permissions will be skipped.
        run 'sudo chmod -R 777 <target directory>'
            example: 'sudo chmod -R 777 /usr/share/sddm/themes'
HELP
}

debug_log "Checking arguments: ARG1='$1' ARG2='$2'"

if [[ -z $1 || -z $2 ]]; then
    error_log "Missing required arguments"
    debug_log "ARG1 (theme name): '$1'"
    debug_log "ARG2 (theme path/url): '$2'"
    ask_help
    exit 1
fi

WALLBASH_DIRS=(
    "${XDG_CONFIG_HOME:-$HOME/.config}/denv/wallbash"
    "${XDG_DATA_HOME:-$HOME/.local/share}/denv/wallbash"
    "/usr/local/share/denv/wallbash"
    "/usr/share/denv/wallbash"
)

debug_log "WALLBASH_DIRS configured:"
for dir in "${WALLBASH_DIRS[@]}"; do
    debug_log "  - $dir (exists: $([ -d "$dir" ] && echo "YES" || echo "NO"))"
done

# set parameters
THEME_NAME="$1"
debug_log "THEME_NAME set to: $THEME_NAME"

debug_log "Checking if ARG2 is directory or URL: $2"
if [ -d "$2" ]; then
    THEME_DIR="$2"
    debug_log "ARG2 is local directory: $THEME_DIR"
    debug_log "Directory contents:"
    ls -la "$THEME_DIR" >&2 2>/dev/null || debug_log "Cannot list directory contents"
else
    debug_log "ARG2 appears to be a URL, processing as git repository"
    git_repo=${2%/}
    debug_log "Git repo URL: $git_repo"
    
    if echo "$git_repo" | grep -q "/tree/"; then
        branch=${git_repo#*tree/}
        git_repo=${git_repo%/tree/*}
        debug_log "Branch extracted from URL: $branch"
        debug_log "Cleaned git repo URL: $git_repo"
    else
        debug_log "No branch in URL, fetching available branches"
        debug_log "Calling GitHub API for: ${git_repo#*://*/}"
        
        # Check if curl and jq are available
        if ! command -v curl >/dev/null 2>&1; then
            error_log "curl is not installed or not in PATH"
            exit 1
        fi
        if ! command -v jq >/dev/null 2>&1; then
            error_log "jq is not installed or not in PATH"
            exit 1
        fi
        
        branches_array=$(curl -s "https://api.github.com/repos/${git_repo#*://*/}/branches" | jq -r '.[].name')
        debug_log "API response for branches: $branches_array"
        
        # shellcheck disable=SC2206
        branches_array=($branches_array)
        debug_log "Available branches: ${branches_array[*]}"
        debug_log "Number of branches: ${#branches_array[@]}"
        
        if [[ ${#branches_array[@]} -le 1 ]]; then
            branch=${branches_array[0]}
            debug_log "Single branch found, using: $branch"
        else
            echo "Select a Branch"
            select branch in "${branches_array[@]}"; do
                [[ -n $branch ]] && break || echo "Invalid selection. Please try again."
            done
            debug_log "User selected branch: $branch"
        fi
    fi

    git_path=${git_repo#*://*/}
    git_owner=${git_path%/*}
    git_theme=${git_path#*/}
    branch_dir=${branch//\//_}
    cache_dir="${XDG_CACHE_HOME:-"$HOME/.cache"}/denv"
    dir_suffix=${git_owner}-${branch_dir}-${git_theme}
    dir_suffix=${dir_suffix//[ \/]/_}
    THEME_DIR="${cache_dir}/themepatcher/${dir_suffix}"

    debug_log "Git processing results:"
    debug_log "  git_path: $git_path"
    debug_log "  git_owner: $git_owner" 
    debug_log "  git_theme: $git_theme"
    debug_log "  branch: $branch"
    debug_log "  branch_dir: $branch_dir"
    debug_log "  cache_dir: $cache_dir"
    debug_log "  dir_suffix: $dir_suffix"
    debug_log "  THEME_DIR: $THEME_DIR"

    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        error_log "git is not installed or not in PATH"
        exit 1
    fi

    if [ -d "$THEME_DIR" ]; then
        print_log "Directory $THEME_DIR" -y " already exists. Using existing directory."
        debug_log "Theme directory exists, attempting git pull"
        debug_log "Current directory before git operations: $(pwd)"
        
        if cd "$THEME_DIR"; then
            debug_log "Successfully changed to $THEME_DIR"
            debug_log "Git status before fetch:"
            git status --short >&2 2>/dev/null || debug_log "Git status failed"
            
            debug_log "Running git fetch --all"
            if git fetch --all &>/dev/null; then
                debug_log "Git fetch successful"
            else
                error_log "Git fetch failed"
            fi
            
            debug_log "Running git reset --hard"
            if git reset --hard "@{upstream}" &>/dev/null; then
                debug_log "Git reset successful"
            else
                error_log "Git reset failed"
            fi
            
            cd - &>/dev/null || {
                error_log "Failed to return to previous directory"
                exit 1
            }
            debug_log "Returned to previous directory: $(pwd)"
        else
            error_log "Could not navigate to $THEME_DIR. Skipping git pull."
        fi
    else
        print_log "Directory $THEME_DIR does not exist. Cloning repository into new directory."
        debug_log "Creating cache directory if it doesn't exist: $(dirname "$THEME_DIR")"
        
        mkdir -p "$(dirname "$THEME_DIR")" || {
            error_log "Failed to create cache directory: $(dirname "$THEME_DIR")"
            exit 1
        }
        
        debug_log "Running git clone: git clone -b '$branch' --depth 1 '$git_repo' '$THEME_DIR'"
        if ! git clone -b "$branch" --depth 1 "$git_repo" "$THEME_DIR" &>/dev/null; then
            error_log "Git clone failed"
            debug_log "Git clone command that failed: git clone -b '$branch' --depth 1 '$git_repo' '$THEME_DIR'"
            exit 1
        fi
        debug_log "Git clone successful"
    fi
fi

debug_log "Final THEME_DIR: $THEME_DIR"
debug_log "THEME_DIR exists: $([ -d "$THEME_DIR" ] && echo "YES" || echo "NO")"

print_log "Patching" -g " --// ${THEME_NAME} //-- " "from " -b "${THEME_DIR}\n"

FAV_THEME_DIR="${THEME_DIR}/Configs/.config/denv/themes/${THEME_NAME}"
debug_log "FAV_THEME_DIR: $FAV_THEME_DIR"
debug_log "FAV_THEME_DIR exists: $([ -d "$FAV_THEME_DIR" ] && echo "YES" || echo "NO")"

if [ ! -d "${FAV_THEME_DIR}" ]; then
    error_log "'${FAV_THEME_DIR}' does not exist"
    debug_log "Contents of ${THEME_DIR}/Configs/.config/denv/themes/:"
    ls -la "${THEME_DIR}/Configs/.config/denv/themes/" >&2 2>/dev/null || debug_log "Cannot list themes directory"
    debug_log "Available themes in directory:"
    find "${THEME_DIR}/Configs/.config/denv/themes/" -maxdepth 1 -type d -name "*" 2>/dev/null | while read -r dir; do
        debug_log "  - $(basename "$dir")"
    done
    exit 1
fi

debug_log "Searching for .dcol files in WALLBASH_DIRS"
config=$(find "${WALLBASH_DIRS[@]}" -type f -path "*/theme*" -name "*.dcol" 2>/dev/null | awk '!seen[substr($0, match($0, /[^/]+$/))]++' | awk -v favTheme="${THEME_NAME}" -F 'theme/' '{gsub(/\.dcol$/, ".theme"); print ".config/denv/themes/" favTheme "/" $2}')
debug_log "Found config files pattern: $config"

restore_list=""
debug_log "Processing config files for restore list:"

while IFS= read -r fileCheck; do
    debug_log "Checking file: $fileCheck"
    if [[ -e "${THEME_DIR}/Configs/${fileCheck}" ]]; then
        print_log -g "[pass]  " "${fileCheck}"
        debug_log "File exists: ${THEME_DIR}/Configs/${fileCheck}"
        file_base=$(basename "${fileCheck}")
        file_dir=$(dirname "${fileCheck}")
        restore_list+="Y|Y|\${HOME}/${file_dir}|${file_base}|hyprland\n"
        debug_log "Added to restore list: Y|Y|\${HOME}/${file_dir}|${file_base}|hyprland"
    else
        print_log -y "[note] " "${fileCheck} --> " -r "do not exist in " "${THEME_DIR}/Configs/"
        debug_log "File missing: ${THEME_DIR}/Configs/${fileCheck}"
    fi
done <<<"$config"

if [ -f "${FAV_THEME_DIR}/theme.dcol" ]; then
    print_log -n "[note] " "found theme.dcol to override wallpaper dominant colors"
    restore_list+="Y|Y|\${HOME}/.config/denv/themes/${THEME_NAME}|theme.dcol|hyprland\n"
    debug_log "Added theme.dcol to restore list"
fi

readonly restore_list
debug_log "Final restore list:"
debug_log "$restore_list"

# Get Wallpapers
debug_log "Searching for wallpapers in: $FAV_THEME_DIR"
wallpapers=$(
    find "${FAV_THEME_DIR}" -type f \( -iname "*.gif" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) ! -path "*/logo/*"
)
wpCount="$(wc -l <<<"${wallpapers}")"
debug_log "Found wallpapers ($wpCount):"
debug_log "$wallpapers"

if [ -z "${wallpapers}" ]; then
    error_log "No wallpapers found"
    debug_log "Contents of FAV_THEME_DIR:"
    find "${FAV_THEME_DIR}" -type f >&2 2>/dev/null || debug_log "Cannot list FAV_THEME_DIR contents"
    exit_flag=true
else
    readonly wallpapers
    print_log -g "\n[pass]  " "wallpapers :: [count] ${wpCount} (.gif+.jpg+.jpeg+.png)"
fi

# Get logos
debug_log "Checking for logos directory: ${FAV_THEME_DIR}/logo"
if [ -d "${FAV_THEME_DIR}/logo" ]; then
    debug_log "Logo directory exists, searching for logo files"
    logos=$(
        find "${FAV_THEME_DIR}/logo" -type f \( -iname "*.gif" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \)
    )
    logosCount="$(wc -l <<<"${logos}")"
    debug_log "Found logos ($logosCount):"
    debug_log "$logos"
    
    if [ -z "${logos}" ]; then
        print_log -y "[note] " "No logos found"
        debug_log "Logo directory exists but no logo files found"
    else
        readonly logos
        print_log -g "[pass]  " "logos :: [count] ${logosCount}\n"
    fi
else
    debug_log "Logo directory does not exist: ${FAV_THEME_DIR}/logo"
fi

# parse thoroughly 😁
check_tars() {
    local trVal
    local inVal="${1}"
    local gsLow
    local gsVal
    
    debug_log "=== Checking tars for: $inVal ==="
    
    gsLow=$(echo "${inVal}" | tr '[:upper:]' '[:lower:]')
    debug_log "Lowercase name: $gsLow"
    debug_log "Looking for hypr.theme file: ${FAV_THEME_DIR}/hypr.theme"
    
    if [ ! -f "${FAV_THEME_DIR}/hypr.theme" ]; then
        error_log "hypr.theme file not found: ${FAV_THEME_DIR}/hypr.theme"
        debug_log "Contents of FAV_THEME_DIR:"
        ls -la "${FAV_THEME_DIR}" >&2 2>/dev/null || debug_log "Cannot list FAV_THEME_DIR"
        exit_flag=true
        return 1
    fi
    
    debug_log "hypr.theme file exists, processing variable extraction"
    
    # Use hyprland variables that are set in the hypr.theme file
    # Using case we can have a predictable output
    gsVal="$(
        case "${gsLow}" in
        sddm)
            grep "^[[:space:]]*\$SDDM[-_]THEME\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        gtk)
            grep "^[[:space:]]*\$GTK[-_]THEME\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        icon)
            grep "^[[:space:]]*\$ICON[-_]THEME\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        cursor)
            grep "^[[:space:]]*\$CURSOR[-_]THEME\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        font)
            grep "^[[:space:]]*\$FONT\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        document-font)
            grep "^[[:space:]]*\$DOCUMENT[-_]FONT\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        monospace-font)
            grep "^[[:space:]]*\$MONOSPACE[-_]FONT\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        bar-font)
            grep "^[[:space:]]*\$BAR[-_]FONT\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        menu-font)
            grep "^[[:space:]]*\$MENU[-_]FONT\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        notification-font)
            grep "^[[:space:]]*\$NOTIFICATION[-_]FONT\s*=" "${FAV_THEME_DIR}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        *) # fallback to older method
            awk -F"[\"']" '/^[[:space:]]*exec[[:space:]]*=[[:space:]]*gsettings[[:space:]]*set[[:space:]]*org.gnome.desktop.interface[[:space:]]*'"${gsLow}"'-theme[[:space:]]*/ {last=$2} END {print last}' "${FAV_THEME_DIR}/hypr.theme"
            ;;
        esac
    )"

    debug_log "Extracted gsVal (method 1): '$gsVal'"

    # fallback to older method
    gsVal=${gsVal:-$(awk -F"[\"']" '/^[[:space:]]*exec[[:space:]]*=[[:space:]]*gsettings[[:space:]]*set[[:space:]]*org.gnome.desktop.interface[[:space:]]*'"${gsLow}"'-theme[[:space:]]*/ {last=$2} END {print last}' "${FAV_THEME_DIR}/hypr.theme")}
    
    debug_log "Final gsVal (after fallback): '$gsVal'"

    if [ -n "${gsVal}" ]; then
        debug_log "gsVal is not empty, processing..."
        
        if [[ "${gsVal}" =~ ^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$ ]]; then # check is a variable is set into a variable eg $FONT=$DOCUMENT_FONT
            print_log -warn "Variable ${gsVal} detected! " "be sure ${gsVal} is set as a different name or on a different file, skipping check"
            debug_log "Variable reference detected: $gsVal"
        else
            print_log -g "[pass]  " "hypr.theme :: [${gsLow}]" -b " ${gsVal}"
            debug_log "Looking for archive: ${THEME_DIR}/${inVal}_*.tar.*"
            
            trArc="$(find "${THEME_DIR}" -type f -name "${inVal}_*.tar.*")"
            debug_log "Found archives: $trArc"
            debug_log "Archive count: $(echo "$trArc" | wc -l)"
            
            if [ -f "${trArc}" ] && [ "$(echo "${trArc}" | wc -l)" -eq 1 ]; then
                debug_log "Single archive found, extracting directory name"
                trVal="$(basename "$(tar -tf "${trArc}" | cut -d '/' -f1 | sort -u)")"
                debug_log "Directory in archive: $trVal"
                trVal="$(echo "${trVal}" | grep -w "${gsVal}")"
                debug_log "Matching directory: $trVal"
            else
                debug_log "No archive found or multiple archives found"
                trVal=""
            fi
            
            print_log -g "[pass]  " "../*.tar.* :: [${gsLow}]" -b " ${trVal}"
            
            if [ "${trVal}" != "${gsVal}" ]; then
                error_log "${gsLow} set in hypr.theme does not exist in ${inVal}_*.tar.*"
                debug_log "Mismatch: hypr.theme has '$gsVal' but archive contains '$trVal'"
                exit_flag=true
            fi
        fi
    else
        debug_log "gsVal is empty"
        if [ "${2}" == "--mandatory" ]; then
            error_log "hypr.theme :: [${gsLow}] Not Found (MANDATORY)"
            debug_log "Mandatory check failed for $gsLow"
            exit_flag=true
            return 0
        fi
        print_log -y "[note] " "hypr.theme :: [${gsLow}] " -r "Not Found, " -y "📣 OPTIONAL package, continuing... "
        debug_log "Optional package $gsLow not found, continuing"
    fi
    
    debug_log "=== End checking tars for: $inVal ==="
}

debug_log "Starting tar checks..."
check_tars Gtk --mandatory
check_tars Icon
check_tars Cursor
check_tars Sddm
check_tars Font
check_tars Document-Font
check_tars Monospace-Font
check_tars Bar-Font
check_tars Menu-Font
check_tars Notification-Font

print_log ""
if [[ "${exit_flag}" = true ]]; then
    error_log "Exiting due to previous errors (exit_flag=true)"
    exit 1
fi

debug_log "All tar checks passed, proceeding with extraction"

# extract arcs
declare -A archive_map=(
    ["Gtk"]="${HOME}/.local/share/themes"
    ["Icon"]="${HOME}/.local/share/icons"
    ["Cursor"]="${HOME}/.local/share/icons"
    ["Sddm"]="/usr/share/sddm/themes"
    ["Font"]="${HOME}/.local/share/fonts"
    ["Document-Font"]="${HOME}/.local/share/fonts"
    ["Monospace-Font"]="${HOME}/.local/share/fonts"
    ["Bar-Font"]="${HOME}/.local/share/fonts"
    ["Menu-Font"]="${HOME}/.local/share/fonts"
    ["Notification-Font"]="${HOME}/.local/share/fonts"
)

debug_log "Archive extraction phase starting"
debug_log "FULL_THEME_UPDATE: ${FULL_THEME_UPDATE:-false}"

for prefix in "${!archive_map[@]}"; do
    debug_log "=== Processing archive type: $prefix ==="
    
    tarFile="$(find "${THEME_DIR}" -type f -name "${prefix}_*.tar.*")"
    debug_log "Looking for archive: ${prefix}_*.tar.* in ${THEME_DIR}"
    debug_log "Found tarFile: $tarFile"
    
    [ -f "${tarFile}" ] || {
        debug_log "No archive file found for $prefix, skipping"
        continue
    }
    
    tgtDir="${archive_map[$prefix]}"
    debug_log "Target directory: $tgtDir"

    if [[ "${tgtDir}" =~ /(usr|usr\/local)\/share/ && -d /run/current-system/sw/share/ ]]; then
        print_log -y "Detected NixOS system, changing target to /run/current-system/sw/share/..."
        tgtDir="/run/current-system/sw/share/"
        debug_log "Changed target for NixOS: $tgtDir"
    fi

    debug_log "Checking if target directory exists: $tgtDir"
    if [ ! -d "${tgtDir}" ]; then
        debug_log "Target directory doesn't exist, creating: $tgtDir"
        if ! mkdir -p "${tgtDir}"; then
            print_log -y "Creating directory as root instead..."
            debug_log "Regular mkdir failed, trying with sudo"
            sudo mkdir -p "${tgtDir}" || {
                error_log "Failed to create directory even with sudo: $tgtDir"
                continue
            }
        fi
        debug_log "Successfully created target directory"
    fi

    debug_log "Extracting directory name from archive"
    tgtChk="$(basename "$(tar -tf "${tarFile}" | cut -d '/' -f1 | sort -u)")"
    debug_log "Directory in archive: $tgtChk"
    debug_log "Full target path would be: ${tgtDir}/${tgtChk}"
    debug_log "Target exists: $([ -d "${tgtDir}/${tgtChk}" ] && echo "YES" || echo "NO")"
    
    if [[ "${FULL_THEME_UPDATE}" != true ]] && [ -d "${tgtDir}/${tgtChk}" ]; then
        print_log -y "[skip] " "\"${tgtDir}/${tgtChk}\"" -y " already exists"
        debug_log "Skipping extraction, directory already exists and FULL_THEME_UPDATE is not true"
        continue
    fi
    
    print_log -g "[extracting] " "${tarFile} --> ${tgtDir}"
    debug_log "Checking if target directory is writable: $tgtDir"
    
    if [ -w "${tgtDir}" ]; then
        debug_log "Target directory is writable, extracting normally"
        if tar -xf "${tarFile}" -C "${tgtDir}"; then
            debug_log "Extraction successful"
        else
            error_log "Normal extraction failed"
        fi
    else
        print_log -y "Not writable. Extracting as root: ${tgtDir}"
        debug_log "Target directory not writable, using sudo"
        if ! sudo tar -xf "${tarFile}" -C "${tgtDir}" 2>/dev/null; then
            print_log -r "Extraction by root FAILED. Giving up..."
            error_log "Sudo extraction also failed"
            print_log "The above error can be ignored if the '${tgtDir}' is not writable..."
        else
            debug_log "Sudo extraction successful"
        fi
    fi
    
    debug_log "=== End processing archive type: $prefix ==="
done

confDir=${XDG_CONFIG_HOME:-"$HOME/.config"}
debug_log "Config directory: $confDir"

# populate wallpaper
theme_wallpapers="${confDir}/denv/themes/${THEME_NAME}/wallpapers"
debug_log "Theme wallpapers directory: $theme_wallpapers"

if [ ! -d "${theme_wallpapers}" ]; then
    debug_log "Creating wallpapers directory"
    mkdir -p "${theme_wallpapers}" || {
        error_log "Failed to create wallpapers directory: $theme_wallpapers"
    }
fi

debug_log "Copying wallpapers..."
while IFS= read -r walls; do
    debug_log "Copying wallpaper: $walls --> $theme_wallpapers"
    if cp -f "${walls}" "${theme_wallpapers}"; then
        debug_log "Successfully copied: $(basename "$walls")"
    else
        error_log "Failed to copy wallpaper: $walls"
    fi
done <<<"${wallpapers}"

# populate logos
theme_logos="${confDir}/denv/themes/${THEME_NAME}/logo"
debug_log "Theme logos directory: $theme_logos"

if [ -n "${logos}" ]; then
    debug_log "Processing logos..."
    if [ ! -d "${theme_logos}" ]; then
        debug_log "Creating logos directory"
        mkdir -p "${theme_logos}" || {
            error_log "Failed to create logos directory: $theme_logos"
        }
    fi
    
    while IFS= read -r logo; do
        debug_log "Processing logo: $logo"
        if [ -f "${logo}" ]; then
            debug_log "Copying logo: $logo --> $theme_logos"
            if cp -f "${logo}" "${theme_logos}"; then
                debug_log "Successfully copied logo: $(basename "$logo")"
            else
                error_log "Failed to copy logo: $logo"
            fi
        else
            print_log -y "[note] " "${logo} --> do not exist"
            debug_log "Logo file does not exist: $logo"
        fi
    done <<<"${logos}"
else
    debug_log "No logos to process"
fi

# restore configs with theme override
debug_log "Creating restore config list file: ${THEME_DIR}/restore_cfg.lst"
echo -en "${restore_list}" >"${THEME_DIR}/restore_cfg.lst"

debug_log "Contents of restore_cfg.lst:"
debug_log "$(cat "${THEME_DIR}/restore_cfg.lst")"

print_log -g "\n[exec] " "restore.config.sh \"${THEME_DIR}/restore_cfg.lst\" \"${THEME_DIR}/Configs\" \"${THEME_NAME}\"\n"

debug_log "Checking if restore.config.sh exists: ${script_dir}/restore.config.sh"
if [ ! -f "${script_dir}/restore.config.sh" ]; then
    error_log "restore.config.sh not found: ${script_dir}/restore.config.sh"
    exit 1
fi

debug_log "Executing restore.config.sh..."
if bash "${script_dir}/restore.config.sh" "${THEME_DIR}/restore_cfg.lst" "${THEME_DIR}/Configs" "${THEME_NAME}" &>/dev/null; then
    debug_log "restore.config.sh completed successfully"
else
    error_log "restore.config.sh failed with exit code $?"
    exit 1
fi

if [ "${3}" != "--skipcaching" ]; then
    debug_log "Running post-processing scripts (not skipping caching)"
    
    debug_log "Checking swwwallcache.sh: ${script_dir}/swwwallcache.sh"
    if [ -f "${script_dir}/swwwallcache.sh" ]; then
        debug_log "Running swwwallcache.sh -t ${THEME_NAME}"
        bash "${script_dir}/swwwallcache.sh" -t "${THEME_NAME}" || {
            error_log "swwwallcache.sh failed"
        }
    else
        error_log "swwwallcache.sh not found: ${script_dir}/swwwallcache.sh"
    fi
    
    debug_log "Checking theme.switch.sh: ${script_dir}/theme.switch.sh"
    if [ -f "${script_dir}/theme.switch.sh" ]; then
        debug_log "Running theme.switch.sh"
        bash "${script_dir}/theme.switch.sh" || {
            error_log "theme.switch.sh failed"
        }
    else
        error_log "theme.switch.sh not found: ${script_dir}/theme.switch.sh"
    fi
else
    debug_log "Skipping caching (--skipcaching flag detected)"
fi

print_log -y "\nNote: " "Warnings are not errors. Review the output to check if it concerns you."

debug_log "=== THEME PATCH DEBUG SESSION COMPLETED SUCCESSFULLY ==="
exit 0
