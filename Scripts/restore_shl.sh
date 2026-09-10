#!/usr/bin/env bash

scrDir="$(dirname "$(realpath "$0")")"
source "${scrDir}/global_fn.sh" || exit 1
flg_DryRun=${flg_DryRun:-0}

if ! chk_list myShell "${shlList[@]}"; then
    print_log -sec SHELL -err error "no supported shell installed"
    exit 1
fi

shell_path="$(command -v "$myShell")"
current_shell="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$current_shell" == "$shell_path" ]]; then
    print_log -sec SHELL -stat exists "$myShell is already the login shell"
elif [[ "$flg_DryRun" -eq 1 ]]; then
    print_log -sec SHELL -stat dry-run "would set login shell to ${shell_path}"
else
    print_log -sec SHELL -stat change "login shell to ${shell_path}"
    chsh -s "$shell_path"
fi
