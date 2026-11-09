#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_help_guard "Usage: hyprshell system/vpn-networkmanager [--connect UUID | --disconnect UUID]
List NetworkManager VPN profiles as JSON or change one." "$@"

note() { send_ephemeral_notif vpn-networkmanager -a VPN -i network-vpn -u "${3:-normal}" "$1" "$2" >/dev/null 2>&1 || true; }
fail() { note "$1" "$2" critical; printf '%s\n' "$2" >&2; exit 1; }
trim_into() { local -n trimmed_ref="$1"; local value="${2#*:}"; trimmed_ref="${value#"${value%%[![:space:]]*}"}"; }
has_openconnect() { local path; for path in /usr/lib/nm-openconnect-auth-dialog /usr/libexec/nm-openconnect-auth-dialog /usr/lib/NetworkManager/nm-openconnect-auth-dialog /usr/lib/networkmanager/nm-openconnect-auth-dialog /usr/lib/*/nm-openconnect-auth-dialog; do [[ -x $path ]] && return; done; return 1; }
install_hint_into() {
  local -n install_hint_ref="$1"
  install_hint_ref=''
  case "$2" in
    wireguard) command -v wg >/dev/null || install_hint_ref='Install wireguard-tools' ;;
    openvpn) command -v openvpn >/dev/null || install_hint_ref='Install openvpn' ;;
    openconnect) has_openconnect || install_hint_ref='Install networkmanager-openconnect' ;;
    vpnc) [[ -x /usr/lib/nm-vpnc-service || -x /usr/libexec/nm-vpnc-service || -x /usr/lib/NetworkManager/nm-vpnc-service ]] || install_hint_ref='Install networkmanager-vpnc' ;;
  esac
}
nmcli_with_notes() {
  local done_title="$1" profile_name="$2" output=''
  shift 2
  output="$(nmcli "$@" 2>&1)" || fail 'VPN Error' "$output"
  note "$done_title" "NetworkManager · $profile_name"
}
snapshot() {
  command -v nmcli >/dev/null || { jq -cn '{available:false,profiles:[],connected:false,active:null}'; return; }
  local raw line name='' uuid='' type='' active='' file='' service='' kind='' install_hint=''
  local -a profile_fields=()
  raw="$(LC_ALL=C nmcli -m multiline -f NAME,UUID,TYPE,ACTIVE,FILENAME connection show 2>/dev/null)" || { jq -cn '{available:true,valid:false,error:"Could not read NetworkManager profiles",profiles:[],connected:false,active:null}'; return; }
  while IFS= read -r line; do
    case "$line" in
      NAME:*) trim_into name "$line" ;; UUID:*) trim_into uuid "$line" ;; TYPE:*) trim_into type "$line" ;;
      ACTIVE:*) trim_into active "$line" ;;
      FILENAME:*)
        trim_into file "$line"; [[ $type == vpn || $type == wireguard ]] || continue
        [[ $file == /run/* || $name == wg0-mullvad* ]] && continue
        if [[ $type == wireguard ]]; then kind=wireguard
        else
          service="$(LC_ALL=C nmcli -g vpn.service-type connection show uuid "$uuid" 2>/dev/null || true)"
          case "$service" in *openconnect*) kind=openconnect ;; *vpnc*) kind=vpnc ;; *openvpn*) kind=openvpn ;; *) continue ;; esac
        fi
        install_hint_into install_hint "$kind"
        profile_fields+=("$name" "$uuid" "$kind" "$active" "$install_hint")
        ;;
    esac
  done <<<"$raw"
  jq -cn '[$ARGS.positional | range(0; length; 5) as $start | .[$start:$start + 5] as [$name, $uuid, $kind, $active, $install_hint] |
    {$name, $uuid, $kind, active: ($active == "yes"), ready: ($install_hint == ""), reason: $install_hint}] as $profiles |
    {available:true,valid:true,profiles:$profiles,connected:any($profiles[];.active),active:(first($profiles[]|select(.active)) // null)}' --args "${profile_fields[@]}"
}

case "${1:-}" in
  '') snapshot ;;
  --connect|--disconnect)
    [[ $# == 2 && $2 =~ ^[[:xdigit:]-]{36}$ ]] || exit 2
    target_uuid="$2"
    data="$(snapshot)"
    profile="$(jq -c --arg id "$target_uuid" '.profiles[]|select(.uuid==$id)' <<<"$data")"
    [[ -n $profile ]] || fail 'VPN Error' 'NetworkManager profile not found'
    name="$(jq -r .name <<<"$profile")"
    if [[ $1 == --disconnect ]]; then
      note 'VPN Disconnecting' "NetworkManager · $name"
      nmcli_with_notes 'VPN Disconnected' "$name" connection down uuid "$target_uuid"
    else
      install_hint="$(jq -r .reason <<<"$profile")"
      [[ -z $install_hint ]] || fail 'VPN Unavailable' "$install_hint"
      note 'VPN Connecting' "NetworkManager · $name"
      if mullvad status -j 2>/dev/null | jq -e '.state != "disconnected"' >/dev/null 2>&1; then
        mullvad disconnect >/dev/null 2>&1 || true
      fi
      while IFS= read -r active_uuid; do
        [[ $active_uuid == "$target_uuid" ]] || nmcli connection down uuid "$active_uuid" >/dev/null 2>&1 || true
      done < <(jq -r '.profiles[]|select(.active)|.uuid' <<<"$data")
      nmcli_with_notes 'VPN Connected' "$name" connection up uuid "$target_uuid"
    fi
    ;;
  *) exit 2 ;;
esac
