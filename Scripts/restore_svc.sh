#!/usr/bin/env bash
#|---/ /+-------------------------+---/ /|#
#|--/ /-| Service restore script  |--/ /-|#
#|/ /---+-------------------------+/ /---|#

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
if ! source "${scrDir}/global_fn.sh"; then
    echo "Error: unable to source global_fn.sh..."
    exit 1
fi

flg_DryRun=${flg_DryRun:-0}

apply_user_presets() {
    if [ "$flg_DryRun" -eq 1 ]; then
        print_log -c "[dry-run] " "systemctl --user daemon-reload"
        print_log -c "[dry-run] " "systemctl --user preset-all --preset-mode=enable-only"
        return 0
    fi

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" || -z "${XDG_RUNTIME_DIR:-}" ]]; then
        print_log -sec "services" -warn "user preset skipped" "DBUS session or XDG_RUNTIME_DIR missing"
        return 1
    fi

    if systemctl --user daemon-reload; then
        print_log -sec "services" -stat "daemon-reload" "user units reloaded"
    else
        print_log -sec "services" -warn "daemon-reload failed" "continuing"
    fi

    if systemctl --user preset-all --preset-mode=enable-only; then
        print_log -sec "services" -stat "preset" "applied user presets (enable-only)"
    elif systemctl --user preset-all; then
        print_log -sec "services" -stat "preset" "applied user presets"
    else
        print_log -sec "services" -warn "preset failed" "continuing"
    fi
}

# Legacy function for backward compatibility with old system_ctl.lst format
handle_legacy_service() {
    local serviceChk="$1"
    
    # Use the original logic for backward compatibility
    if [[ $(systemctl list-units --all -t service --full --no-legend "${serviceChk}.service" | sed 's/^\s*//g' | cut -f1 -d' ') == "${serviceChk}.service" ]]; then
        print_log -y "[skip] " -b "active " "Service ${serviceChk}"
    else
        print_log -y "enable " "Service ${serviceChk}"
        if [ "$flg_DryRun" -ne 1 ]; then
            sudo systemctl enable "${serviceChk}.service"
        fi
    fi
}

# Main processing
print_log -sec "services" -stat "restore" "system services..."
apply_user_presets || true

while IFS='|' read -r service context command || [ -n "$service" ]; do
    # Skip empty lines and comments
    [[ -z "$service" || "$service" =~ ^[[:space:]]*# ]] && continue
    
    # Trim whitespace
    service=$(echo "$service" | xargs)
    context=$(echo "$context" | xargs)
    command=$(echo "$command" | xargs)
    
    # Check if this is the new pipe-delimited format or legacy format
    if [[ -z "$context" ]]; then
        # Legacy format: service name only
        handle_legacy_service "$service"
    else
        # New format: service|context|command
        # Parse command into array to handle spaces properly
        read -ra cmd_array <<< "$command"
        
        print_log -y "[exec] " "Service ${service} (${context}): $command"
        
        if [ "$flg_DryRun" -ne 1 ]; then
            if [ "$context" = "user" ] ; then
            if [[ -n "${DBUS_SESSION_BUS_ADDRESS}" ]] && [[ -n $XDG_RUNTIME_DIR ]];then
                systemctl --user "${cmd_array[@]}" "${service}.service"
            else 
             print_log -sec "services" -stat "error" "DBUS_SESSION_BUS_ADDRESS or XDG_RUNTIME_DIR not set for user service" -y " skipping"
            fi
            else
                sudo systemctl "${cmd_array[@]}" "${service}.service"
            fi
        else
            if [ "$context" = "user" ]; then
                print_log -c "[dry-run] " "systemctl --user ${cmd_array[*]} ${service}.service"
            else
                print_log -c "[dry-run] " "sudo systemctl ${cmd_array[*]} ${service}.service"
            fi
        fi
    fi
    
done < "${scrDir}/restore_svc.lst"

print_log -sec "services" -stat "completed" "service updated successfully"
