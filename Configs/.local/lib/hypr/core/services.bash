#!/usr/bin/env bash

hypr_init_system() {
  if [[ -n "${HYPR_INIT_SYSTEM:-}" ]]; then
    printf '%s\n' "${HYPR_INIT_SYSTEM}"
    return 0
  fi

  local detected="other"
  if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    detected="systemd"
  elif command -v sv >/dev/null 2>&1 && { [[ -d /run/runit ]] || [[ -d /etc/runit ]]; }; then
    detected="runit"
  fi

  export HYPR_INIT_SYSTEM="${detected}"
  printf '%s\n' "${detected}"
}

hypr_user_sv_dir() {
  printf '%s\n' "${HYPR_USER_SV_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sv}"
}

hypr_svc_user() {
  local action="${1:-}" name="${2:-}"
  [[ -n "${action}" && -n "${name}" ]] || return 2

  hypr_init_system >/dev/null
  case "$HYPR_INIT_SYSTEM" in
    systemd)
      local unit="${name%.service}.service"
      case "${action}" in
        start)     systemctl --user start --no-block "${unit}" >/dev/null 2>&1 ;;
        stop)      systemctl --user stop "${unit}" >/dev/null 2>&1 ;;
        restart)   systemctl --user restart "${unit}" >/dev/null 2>&1 ;;
        is-active) systemctl --user is-active --quiet "${unit}" >/dev/null 2>&1 ;;
        status)    systemctl --user status "${unit}" --no-pager ;;
        enable)    systemctl --user enable "${unit}" ;;
        disable)   systemctl --user disable "${unit}" ;;
        reset-failed) systemctl --user reset-failed "${unit}" >/dev/null 2>&1 ;;
        *) return 2 ;;
      esac
      ;;
    runit)
      command -v sv >/dev/null 2>&1 || return 1
      local svc="${name%.service}"
      local sv_dir; sv_dir="$(hypr_user_sv_dir)"
      local svc_dir="${sv_dir}/${svc}"
      case "${action}" in
        start)     SVDIR="${sv_dir}" sv up "${svc}" >/dev/null 2>&1 ;;
        stop)      SVDIR="${sv_dir}" sv down "${svc}" >/dev/null 2>&1 ;;
        restart)   SVDIR="${sv_dir}" sv restart "${svc}" >/dev/null 2>&1 ;;
        is-active) SVDIR="${sv_dir}" sv status "${svc}" 2>/dev/null | grep -q '^run:' ;;
        status)    SVDIR="${sv_dir}" sv status "${svc}" ;;
        enable)    [[ -d "${svc_dir}" ]] && rm -f -- "${svc_dir}/down" ;;
        disable)   [[ -d "${svc_dir}" ]] && : >"${svc_dir}/down" ;;
        reset-failed) return 0 ;;
        *) return 2 ;;
      esac
      ;;
    *)
      case "$action" in is-active | status | enable | disable) return 1 ;; *) return 0 ;; esac
      ;;
  esac
}

hypr_svc_user_signal() {
  local name="${1:-}" sig="${2:-}"
  [[ -n "${name}" && -n "${sig}" ]] || return 2

  hypr_init_system >/dev/null
  case "$HYPR_INIT_SYSTEM" in
    systemd)
      systemctl --user kill --signal="${sig}" "${name%.service}.service" >/dev/null 2>&1
      ;;
    runit)
      command -v sv >/dev/null 2>&1 || return 1
      local sv_cmd=""
      case "${sig#SIG}" in
        USR1) sv_cmd="1" ;;
        USR2) sv_cmd="2" ;;
        HUP)  sv_cmd="hup" ;;
        TERM) sv_cmd="term" ;;
        INT)  sv_cmd="interrupt" ;;
        KILL) sv_cmd="kill" ;;
        *) return 1 ;;
      esac
      SVDIR="$(hypr_user_sv_dir)" sv "${sv_cmd}" "${name%.service}" >/dev/null 2>&1
      ;;
    *)
      return 0
      ;;
  esac
}
