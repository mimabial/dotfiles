#!/usr/bin/env bash

scrDir="$(dirname "$(realpath "$0")")"
source "${scrDir}/global_fn.sh" || exit 1
flg_DryRun=${flg_DryRun:-0}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    printf '%s' "${value%"${value##*[![:space:]]}"}"
}

apply_user_presets() {
    if [ "$flg_DryRun" -eq 1 ]; then
        print_log -c "[dry-run] " "systemctl --user daemon-reload and preset-all"
        return
    fi
    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" || -z "${XDG_RUNTIME_DIR:-}" ]]; then
        print_log -sec services -warn "user preset skipped" "session environment missing"
        return
    fi
    systemctl --user daemon-reload || print_log -sec services -warn "daemon-reload failed" continuing
    systemctl --user preset-all --preset-mode=enable-only || systemctl --user preset-all || print_log -sec services -warn "preset failed" continuing
}

print_log -sec services -stat restore "system services..."
apply_user_presets

while IFS='|' read -r service context action || [ -n "$service" ]; do
    [[ -n "$service" && "$service" != \#* ]] || continue
    service="$(trim "$service")"
    context="$(trim "$context")"
    action="$(trim "$action")"
    read -ra command <<<"$action"
    [[ -n "$service" && ${#command[@]} -gt 0 ]] || continue

    print_log -y "[exec] " "Service ${service} (${context}): ${action}"
    if [ "$flg_DryRun" -eq 1 ]; then
        [[ "$context" == user ]] && prefix="systemctl --user" || prefix="sudo systemctl"
        print_log -c "[dry-run] " "${prefix} ${action} ${service}.service"
    elif [[ "$context" == user ]]; then
        if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
            systemctl --user "${command[@]}" "${service}.service"
        else
            print_log -sec services -err error "session environment missing; skipping ${service}"
        fi
    elif [[ "$context" == root ]]; then
        sudo systemctl "${command[@]}" "${service}.service"
    else
        print_log -sec services -err error "invalid context '${context}' for ${service}"
    fi
done <"${scrDir}/restore_svc.lst"

print_log -sec services -stat completed "services updated"
