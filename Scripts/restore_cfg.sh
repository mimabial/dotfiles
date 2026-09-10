#!/usr/bin/env bash

# shellcheck disable=SC2034
log_section=deploy
scrDir="$(dirname "$(realpath "$0")")"
source "${scrDir}/global_fn.sh" || exit 1
flg_DryRun=${flg_DryRun:-0}

expand_home_path() {
    local value="$1"
    value="${value//'${HOME}'/${HOME}}"
    printf '%s\n' "${value//\$HOME/${HOME}}"
}

ensure_dir() {
    [[ -d "$1" || "$flg_DryRun" -eq 1 ]] || mkdir -p "$1"
}

dependencies_ready() {
    local package
    for package in $1; do
        pkg_installed "$package" || return 1
    done
}

apply_item() {
    local mode="$1" parent="$2" item="$3"
    local rel="${parent#"$HOME"}" target="${parent}/${item}"
    local source="${CfgDir}${rel}/${item}" backup="${BkpDir}${rel}"

    if [[ "$mode" == T ]]; then
        ensure_dir "$backup"
        if [[ ! -e "$target" ]]; then
            print_log -y "[trash]" -b " :: " "Target missing: ${target}"
        elif [[ "$flg_DryRun" -eq 1 ]]; then
            print_log -y "[dry-run]" -b " :: " "Would trash ${target} --> ${backup}"
        elif mv "$target" "$backup"; then
            print_log -r "[trash]" -b " :: " "${target} --> ${backup}"
        else
            print_log -r "[error]" -b " :: " "Failed to move ${target} to ${backup}"
        fi
        return
    fi

    if [[ "$mode" != B && ! -e "$source" ]]; then
        print_log -y "[skip]" -b " no source :: " "$source"
        return
    fi

    ensure_dir "$parent"
    if [[ ! -e "$target" ]]; then
        if [[ "$mode" != B ]]; then
            [[ "$flg_DryRun" -eq 1 ]] || cp -r "$source" "$parent"
            print_log -y "[populate]" -b " :: " "${target} <-- ${source}"
        fi
        return
    fi

    ensure_dir "$backup"
    case "$mode" in
    B)
        [[ "$flg_DryRun" -eq 1 ]] || cp -r "$target" "$backup"
        print_log -g "[backup]" -b " :: " "${target} --> ${backup}"
        ;;
    O)
        if [[ "$flg_DryRun" -ne 1 ]]; then
            mv "$target" "$backup"
            cp -r "$source" "$parent"
        fi
        print_log -r "[backup + overwrite]" -b " :: " "${target} <-- ${source}"
        ;;
    S)
        if [[ "$flg_DryRun" -ne 1 ]]; then
            cp -r "$target" "$backup"
            cp -rf "$source" "$parent"
        fi
        print_log -y "[backup + sync]" -b " :: " "${target} <-- ${source}"
        ;;
    P)
        if [[ "$flg_DryRun" -ne 1 ]]; then
            cp -r "$target" "$backup"
            cp -rn "$source" "$parent"
        fi
        print_log -g "[backup + preserve]" -b " :: " "$target"
        ;;
    esac
}

deploy_psv() {
    local row mode parent items packages item
    while IFS= read -r row || [[ -n "$row" ]]; do
        if [[ "$row" != *'|'* ]]; then
            [[ "$row" == \ * ]] && {
                echo
                print_log -b "$row"
            }
            continue
        fi
        IFS='|' read -r mode parent items packages <<<"$row"
        [[ -n "$mode" && "$mode" != \#* ]] || continue
        parent="$(expand_home_path "$parent")"
        if [[ "$mode" == I ]]; then
            print_log -r "[ignore] :: " "${parent}/${items}"
            continue
        fi
        [[ "$mode" == B || "$mode" == O || "$mode" == P || "$mode" == S || "$mode" == T ]] || {
            print_log -r "[error] :: " "Unknown mode '${mode}'"
            continue
        }
        if [[ -n "${packages// /}" ]] && ! dependencies_ready "$packages"; then
            print_log -y "[skip] " -r missing -b " :: " "${parent}/${items}"
            continue
        fi
        for item in $items; do
            [[ -n "$parent" ]] && apply_item "$mode" "$parent" "$item"
        done
    done <"$CfgLst"
}

hyprland_hook() {
    local source="${CfgDir}/.config/hypr/hyprland.lua"
    local target="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
    local backup="${BkpDir}/.config/hypr"
    [[ -f "$source" ]] || {
        print_log -r "[error] :: " "Template missing: ${source}"
        return 1
    }
    [[ ! -f "$target" ]] || ! grep -Eq '^local core = require\("core"\)' "$target" || return 0
    ensure_dir "${target%/*}"
    ensure_dir "$backup"
    if [[ "$flg_DryRun" -ne 1 ]]; then
        [[ ! -f "$target" ]] || cp -f "$target" "$backup/hyprland.lua"
        cp -f "$source" "$target"
    fi
    print_log -g "[restore] :: " "${source} --> ${target}"
}

default_list="${scrDir}/${USER}-restore_cfg.psv"
[[ -f "$default_list" ]] || default_list="${scrDir}/restore_cfg.psv"
CfgLst="${1:-$default_list}"
CfgDir="${2:-${cloneDir}/Configs}"
ThemeOverride="${3:-}"
[[ -f "$CfgLst" && -d "$CfgDir" ]] || {
    echo "ERROR: '${CfgLst}' or '${CfgDir}' does not exist" >&2
    exit 1
}

BkpDir="${HOME}/.config/cfg_backups/$(date +'%y%m%d_%Hh%Mm%Ss')${ThemeOverride}"
[[ ! -d "$BkpDir" ]] || {
    echo "ERROR: ${BkpDir} exists" >&2
    exit 1
}
ensure_dir "$BkpDir"

print_log -g "[manifest]" -b " :: " "$CfgLst"
deploy_psv
echo
hyprland_hook

if [[ "$flg_DryRun" -ne 1 ]]; then
    print_log -g "[python env]" -b " :: " "Rebuilding Hypr Python environment..."
    "${HOME}/.local/bin/hyprshell" pyinit
    print_log -g "[version]" -b " :: " "Saving version info..."
    "${scrDir}/version.sh" --cache || echo "Failed to save version info."
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
    mkdir -p "$state_dir"
    [[ -f "${cloneDir}/CHANGELOG.md" ]] && cp -f "${cloneDir}/CHANGELOG.md" "$state_dir/CHANGELOG.md"
fi
