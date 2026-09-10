#!/usr/bin/env bash
scrDir=$(dirname "$(realpath "$0")")
if ! source "${scrDir}/global_fn.sh"; then
    echo "Error: unable to source global_fn.sh..."
    exit 1
fi

verbose="${4}"
set +e

print_prompt() {
    [[ "${verbose}" == false ]] || print_log "$@"
}

ask_help() {
    cat <<HELP
Usage:
    $(print_prompt "$0 " -y "Theme-Name " -c "/Path/to/Configs")
    $(print_prompt "$0 " -y "Theme-Name " -c "https://github.com/User/Repository")
    $(print_prompt "$0 " -y "Theme-Name " -c "https://github.com/User/Repository/tree/branch")

Options:
    'export FULL_THEME_UPDATE=true'       Overwrites the archived files (useful for updates and changes in archives)

Supported Archive Format:
    | File prfx          | Hyprland variable | Target dir                      |
    | ---------------    | ----------------- | --------------------------------|
    | Gtk_               | \$GTK_THEME        | \$HOME/.local/share/themes     |
    | Icon_              | \$ICON_THEME       | \$HOME/.local/share/icons      |
    | Cursor_            | \$CURSOR_THEME     | \$HOME/.local/share/icons      |
    | Font_              | \$FONT             | \$HOME/.local/share/fonts      |
    | Document-Font_     | \$DOCUMENT_FONT    | \$HOME/.local/share/fonts      |
    | Monospace-Font_    | \$MONOSPACE_FONT   | \$HOME/.local/share/fonts      |
    | Notification-Font_ | \$NOTIFICATION_FONT | \$HOME/.local/share/fonts  |
    | Bar-Font_          | \$BAR_FONT         | \$HOME/.local/share/fonts      |
    | Menu-Font_         | \$MENU_FONT        | \$HOME/.local/share/fonts      |

Note:
    Target directories without enough permissions will be skipped.
        run 'sudo chmod -R 777 <target directory>'
HELP
}

if [[ -z $1 || -z $2 ]]; then
    ask_help
    exit 1
fi

Fav_Theme="$1"

if [ -d "$2" ]; then
    Theme_Dir="$2"
else
    Git_Repo=${2%/}
    if echo "$Git_Repo" | grep -q "/tree/"; then
        branch=${Git_Repo#*tree/}
        Git_Repo=${Git_Repo%/tree/*}
    else
        branches=$(curl -s "https://api.github.com/repos/${Git_Repo#*://*/}/branches" | jq -r '.[].name')
        # shellcheck disable=SC2206
        branches=($branches)
        if [[ ${#branches[@]} -le 1 ]]; then
            branch=${branches[0]}
        else
            echo "Select a Branch"
            select branch in "${branches[@]}"; do
                [[ -n $branch ]] && break || echo "Invalid selection. Please try again."
            done
        fi
    fi

    Git_Path=${Git_Repo#*://*/}
    Git_Owner=${Git_Path%/*}
    branch_dir=${branch//\//_}
    cacheDir=${cacheDir:-"$HOME/.cache/hypr"}
    Theme_Dir="${cacheDir}/themepatcher/${branch_dir}-${Git_Owner}"

    if [ -d "$Theme_Dir" ]; then
        print_prompt "Directory $Theme_Dir already exists. Using existing directory."
        if cd "$Theme_Dir"; then
            git fetch --all &>/dev/null
            git reset --hard "@{upstream}" &>/dev/null
            cd - &>/dev/null || exit
        else
            print_prompt -y "Could not navigate to $Theme_Dir. Skipping git pull."
        fi
    else
        print_prompt "Directory $Theme_Dir does not exist. Cloning repository into new directory."
        if ! git clone -b "$branch" --depth 1 "$Git_Repo" "$Theme_Dir" &>/dev/null; then
            print_prompt "Git clone failed"
            exit 1
        fi
    fi
fi

print_prompt "Patching" -g " --// ${Fav_Theme} //-- " "from " -b "${Theme_Dir}\n"

Fav_Theme_Dir="${Theme_Dir}/Configs/.config/hypr/themes/${Fav_Theme}"
[ ! -d "${Fav_Theme_Dir}" ] && print_prompt -r "[ERROR] " "'${Fav_Theme_Dir}'" -y " Do not Exist" && exit 1

restore_list="S|\${HOME}/.config/hypr/themes/${Fav_Theme}|.|hyprland\n"
readonly restore_list

wallpaper="$(find "${Fav_Theme_Dir}" -type f \( -iname '*.gif' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) ! -path '*/logo/*' -print -quit)"
[[ -n "$wallpaper" ]] || {
    print_prompt -r "[ERROR] " "No wallpapers found"
    exit 1
}

check_tars() {
    local trVal
    local inVal="${1}"
    local gsLow
    local gsVal
    gsLow=$(echo "${inVal}" | tr '[:upper:]' '[:lower:]')
    gsVal="$(
        case "${gsLow}" in
        gtk)
            grep "^[[:space:]]*\$GTK[-_]THEME\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        icon)
            grep "^[[:space:]]*\$ICON[-_]THEME\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        cursor)
            grep "^[[:space:]]*\$CURSOR[-_]THEME\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        font)
            grep "^[[:space:]]*\$FONT\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        document-font)
            grep "^[[:space:]]*\$DOCUMENT[-_]FONT\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        monospace-font)
            grep "^[[:space:]]*\$MONOSPACE[-_]FONT\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        bar-font)
            grep "^[[:space:]]*\$BAR[-_]FONT\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        menu-font)
            grep "^[[:space:]]*\$MENU[-_]FONT\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        notification-font)
            grep "^[[:space:]]*\$NOTIFICATION[-_]FONT\s*=" "${Fav_Theme_Dir}/hypr.theme" | cut -d '=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;

        *)
            awk -F"[\"']" '/^[[:space:]]*exec[[:space:]]*=[[:space:]]*gsettings[[:space:]]*set[[:space:]]*org.gnome.desktop.interface[[:space:]]*'"${gsLow}"'-theme[[:space:]]*/ {last=$2} END {print last}' "${Fav_Theme_Dir}/hypr.theme"
            ;;
        esac
    )"

    gsVal=${gsVal:-$(awk -F"[\"']" '/^[[:space:]]*exec[[:space:]]*=[[:space:]]*gsettings[[:space:]]*set[[:space:]]*org.gnome.desktop.interface[[:space:]]*'"${gsLow}"'-theme[[:space:]]*/ {last=$2} END {print last}' "${Fav_Theme_Dir}/hypr.theme")}

    if [ -n "${gsVal}" ]; then

        if [[ "${gsVal}" =~ ^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$ ]]; then
            print_prompt -y "[warn] " "Variable ${gsVal} detected,be sure ${gsVal} is set in hypr.theme, skipping check"
        else
            print_prompt -g "[OK] " "hypr.theme :: [${gsLow}]" -b " ${gsVal}"
            trArc="$(find "${Theme_Dir}" -type f -name "${inVal}_*.tar.*")"
            [ -f "${trArc}" ] && [ "$(echo "${trArc}" | wc -l)" -eq 1 ] && trVal="$(basename "$(tar -tf "${trArc}" | cut -d '/' -f1 | sort -u)")" && trVal="$(echo "${trVal}" | grep -w "${gsVal}")"
            print_prompt -g "[OK] " "../*.tar.* :: [${gsLow}]" -b " ${trVal}"
            [ "${trVal}" != "${gsVal}" ] && print_prompt -r "[ERROR] " "${gsLow} set in hypr.theme does not exist in ${inVal}_*.tar.*" && exit_flag=true
        fi
    else
        [ "${2}" == "--mandatory" ] && print_prompt -r "[ERROR] " "hypr.theme :: [${gsLow}] Not Found" && exit_flag=true && return 0
        print_prompt -y "[warn] " "hypr.theme :: [${gsLow}] Not Found, don't worry if it's not needed"
    fi
}

check_tars Gtk --mandatory
check_tars Icon
check_tars Cursor
check_tars Font
check_tars Document-Font
check_tars Monospace-Font
check_tars Bar-Font
check_tars Menu-Font
check_tars Notification-Font
print_prompt "" && [[ "${exit_flag}" = true ]] && exit 1

declare -A archive_map=(
    ["Gtk"]="${HOME}/.local/share/themes"
    ["Icon"]="${HOME}/.local/share/icons"
    ["Cursor"]="${HOME}/.local/share/icons"
    ["Font"]="${HOME}/.local/share/fonts"
    ["Document-Font"]="${HOME}/.local/share/fonts"
    ["Monospace-Font"]="${HOME}/.local/share/fonts"
    ["Bar-Font"]="${HOME}/.local/share/fonts"
    ["Menu-Font"]="${HOME}/.local/share/fonts"
    ["Notification-Font"]="${HOME}/.local/share/fonts"
)

for prefix in "${!archive_map[@]}"; do
    tarFile="$(find "${Theme_Dir}" -type f -name "${prefix}_*.tar.*")"
    [ -f "${tarFile}" ] || continue
    tgtDir="${archive_map[$prefix]}"

    if [[ "${tgtDir}" =~ /(usr|usr\/local)\/share/ && -d /run/current-system/sw/share/ ]]; then
        print_prompt -y "Detected NixOS system, changing target to /run/current-system/sw/share/..."
        tgtDir="/run/current-system/sw/share/"
    fi

    if [ ! -d "${tgtDir}" ]; then
        if ! mkdir -p "${tgtDir}"; then
            print_prompt -y "Creating directory as root instead..."
            sudo mkdir -p "${tgtDir}"
        fi
    fi

    tgtChk="$(basename "$(tar -tf "${tarFile}" | cut -d '/' -f1 | sort -u)")"
    [[ "${FULL_THEME_UPDATE}" = true ]] || { [ -d "${tgtDir}/${tgtChk}" ] && print_prompt -y "[skip] " "\"${tgtDir}/${tgtChk}\" already exists" && continue; }
    print_prompt -g "[extracting] " "${tarFile} --> ${tgtDir}"

    if [ -w "${tgtDir}" ]; then
        tar -xf "${tarFile}" -C "${tgtDir}"
    else
        print_prompt -y "Not writable. Extracting as root: ${tgtDir}"
        if ! sudo tar -xf "${tarFile}" -C "${tgtDir}" 2>/dev/null; then
            print_prompt -r "Extraction by root FAILED. Giving up..."
            print_prompt "The above error can be ignored if the '${tgtDir}' is not writable..."
        fi
    fi

done

printf '%b' "${restore_list}" >"${Theme_Dir}/restore_cfg.psv"
print_prompt -g "\n[exec] " "restore_cfg.sh \"${Theme_Dir}/restore_cfg.psv\" \"${Theme_Dir}/Configs\" \"${Fav_Theme}\"\n"
"${scrDir}/restore_cfg.sh" "${Theme_Dir}/restore_cfg.psv" "${Theme_Dir}/Configs" "${Fav_Theme}" &>/dev/null
if [ "${3}" != "--skipcaching" ]; then
    if command -v hyprshell >/dev/null 2>&1; then
        hyprshell wallpaper/wallpaper.cache -f
        hyprshell theme/theme.switch -q
    else
        "$HOME/.local/lib/hypr/wallpaper/wallpaper.cache.sh" -f
        "$HOME/.local/lib/hypr/theme/theme.switch.sh" -q
    fi
fi

print_prompt -y "\nNote: Warnings are not errors. Review the output to check if it concerns you."

exit 0
