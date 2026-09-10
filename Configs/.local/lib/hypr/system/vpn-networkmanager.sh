#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_help_guard "Usage: hyprshell system/vpn-networkmanager [--connect UUID | --disconnect UUID]
List NetworkManager VPN profiles as JSON or change one." "$@"

note() { send_ephemeral_notif vpn-networkmanager -a VPN -i network-vpn -u "${3:-normal}" "$1" "$2" >/dev/null 2>&1 || true; }
trim() { local value="${1#*:}"; printf '%s' "${value#"${value%%[![:space:]]*}"}"; }
has_openconnect() { local path; for path in /usr/lib/nm-openconnect-auth-dialog /usr/libexec/nm-openconnect-auth-dialog /usr/lib/NetworkManager/nm-openconnect-auth-dialog /usr/lib/networkmanager/nm-openconnect-auth-dialog /usr/lib/*/nm-openconnect-auth-dialog; do [[ -x $path ]] && return; done; return 1; }
carrier() {
  case "$1" in
    wireguard) command -v wg >/dev/null && printf 'true\034' || printf 'false\034Install wireguard-tools' ;;
    openvpn) command -v openvpn >/dev/null && printf 'true\034' || printf 'false\034Install openvpn' ;;
    openconnect) has_openconnect && printf 'true\034' || printf 'false\034Install networkmanager-openconnect' ;;
    vpnc) [[ -x /usr/lib/nm-vpnc-service || -x /usr/libexec/nm-vpnc-service || -x /usr/lib/NetworkManager/nm-vpnc-service ]] && printf 'true\034' || printf 'false\034Install networkmanager-vpnc' ;;
  esac
}
snapshot() {
  command -v nmcli >/dev/null || { jq -cn '{available:false,profiles:[],connected:false,active:null}'; return; }
  local raw line name='' uuid='' type='' active='' file='' service='' kind='' check ready reason
  local -a fields=()
  raw="$(LC_ALL=C nmcli -m multiline -f NAME,UUID,TYPE,ACTIVE,FILENAME connection show 2>/dev/null)" || { jq -cn '{available:true,valid:false,error:"Could not read NetworkManager profiles",profiles:[],connected:false,active:null}'; return; }
  while IFS= read -r line; do
    case "$line" in
      NAME:*) name="$(trim "$line")" ;; UUID:*) uuid="$(trim "$line")" ;; TYPE:*) type="$(trim "$line")" ;;
      ACTIVE:*) active="$(trim "$line")" ;;
      FILENAME:*)
        file="$(trim "$line")"; [[ $type == vpn || $type == wireguard ]] || continue
        [[ $file == /run/* || $name == wg0-mullvad* ]] && continue
        if [[ $type == wireguard ]]; then kind=wireguard
        else
          service="$(LC_ALL=C nmcli -g vpn.service-type connection show uuid "$uuid" 2>/dev/null || true)"
          case "$service" in *openconnect*) kind=openconnect ;; *vpnc*) kind=vpnc ;; *openvpn*) kind=openvpn ;; *) continue ;; esac
        fi
        check="$(carrier "$kind")"; IFS=$'\034' read -r ready reason <<<"$check"
        fields+=("$name" "$uuid" "$kind" "$active" "$ready" "${reason:-}")
        ;;
    esac
  done <<<"$raw"
  jq -cn '$ARGS.positional as $a | [range(0; $a|length; 6) as $i |
    {name:$a[$i],uuid:$a[$i+1],kind:$a[$i+2],active:($a[$i+3]=="yes"),ready:($a[$i+4]=="true"),reason:$a[$i+5]}] as $p |
    {available:true,valid:true,profiles:$p,connected:any($p[];.active),active:(first($p[]|select(.active)) // null)}' --args "${fields[@]}"
}

case "${1:-}" in
  '') snapshot ;;
  --connect|--disconnect)
    [[ $# == 2 && $2 =~ ^[[:xdigit:]-]{36}$ ]] || exit 2
    data="$(snapshot)"; profile="$(jq -c --arg id "$2" '.profiles[]|select(.uuid==$id)' <<<"$data")"
    [[ -n $profile ]] || { note 'VPN Error' 'NetworkManager profile not found' critical; exit 1; }
    name="$(jq -r .name <<<"$profile")"
    if [[ $1 == --disconnect ]]; then
      note 'VPN Disconnecting' "NetworkManager · $name"
      if output="$(nmcli connection down uuid "$2" 2>&1)"; then note 'VPN Disconnected' "NetworkManager · $name"; else note 'VPN Error' "$output" critical; printf '%s\n' "$output" >&2; exit 1; fi
    else
      reason="$(jq -r 'select(.ready|not)|.reason' <<<"$profile")"; [[ -z $reason ]] || { note 'VPN Unavailable' "$reason" critical; printf '%s\n' "$reason" >&2; exit 1; }
      note 'VPN Connecting' "NetworkManager · $name"
      mullvad status -j 2>/dev/null | jq -e '.state != "disconnected"' >/dev/null 2>&1 && mullvad disconnect >/dev/null 2>&1 || true
      while IFS= read -r id; do [[ $id == "$2" ]] || nmcli connection down uuid "$id" >/dev/null 2>&1 || true; done < <(jq -r '.profiles[]|select(.active)|.uuid' <<<"$data")
      if output="$(nmcli connection up uuid "$2" 2>&1)"; then note 'VPN Connected' "NetworkManager · $name"; else note 'VPN Error' "$output" critical; printf '%s\n' "$output" >&2; exit 1; fi
    fi
    ;;
  *) exit 2 ;;
esac
