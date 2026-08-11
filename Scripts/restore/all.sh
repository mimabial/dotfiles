#!/usr/bin/env bash

set -e

scrDir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
# shellcheck disable=SC1091
source "${scrDir}/global_fn.sh" || exit 1

flg_DryRun=${flg_DryRun:-0}

refresh_generated_outputs() {
    print_log -g "[generate] " "cache ::" "Wallpapers and themed outputs..."

    if [ "${flg_DryRun}" -eq 1 ]; then
        print_log -y "[dry-run] " "would refresh wallpaper cache, theme, and waybar"
        return 0
    fi

    export PATH="$HOME/.local/lib/hypr:$HOME/.local/bin:${PATH}"

    if command -v hyprshell >/dev/null 2>&1; then
        hyprshell wallpaper/wallpaper.cache -f || print_log -warn "wallpaper cache" "refresh failed"
        hyprshell theme/theme.switch -q || print_log -warn "theme" "refresh failed"
        hyprshell waybar/waybar --update || print_log -warn "waybar" "refresh failed"
    else
        if [ -x "$HOME/.local/lib/hypr/wallpaper/wallpaper.cache.sh" ]; then
            "$HOME/.local/lib/hypr/wallpaper/wallpaper.cache.sh" -f || print_log -warn "wallpaper cache" "refresh failed"
        fi
        "$HOME/.local/lib/hypr/theme/theme.switch.sh" -q || print_log -warn "theme" "refresh failed"
        "$HOME/.local/lib/hypr/waybar/waybar.py" --update || print_log -warn "waybar" "refresh failed"
    fi

    echo "[install] reload :: Hyprland"
}

restore_host_layer() {
    local apply_args=()
    [ "${flg_DryRun}" -eq 1 ] && apply_args+=(--dry-run)

    if ! command -v dotfiles-host-profile >/dev/null 2>&1; then
        print_log -warn "host profile" "dotfiles-host-profile not found"
        return 0
    fi

    dotfiles-host-profile apply "${apply_args[@]}" || print_log -warn "host profile" "apply failed"
}

seed_hypr_state() {
    local seed_args=(--mode restore hypr-state)
    [ "${flg_DryRun}" -eq 1 ] && seed_args+=(-n)

    if ! command -v hyprshell >/dev/null 2>&1; then
        print_log -warn "hypr state" "hyprshell not found"
        return 0
    fi

    hyprshell service/managed.sh "${seed_args[@]}" || print_log -warn "hypr state" "seed failed"
}

if [ "${flg_DryRun}" -ne 1 ] && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl dispatch '(function() hl.config({misc = {disable_autoreload = true}}); return hl.dsp.no_op() end)()' >/dev/null
fi

run_step "restore configs" "${scrDir}/restore_cfg.sh"
run_step "restore host layer" restore_host_layer
run_step "seed hypr state" seed_hypr_state
run_step "restore themes" "${scrDir}/restore_thm.sh"
run_step "refresh generated outputs" refresh_generated_outputs
