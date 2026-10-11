vpn_mullvad_status() {
  mullvad status 2>&1
}

vpn_parse_mullvad_status_into() {
  local -n parsed_status_ref="$1"
  local line="" value="" field_index=0
  local -a fields=()
  parsed_status_ref=([state]="" [relay]="" [location]="" [ipv4]="")
  {
    IFS= read -r line
    parsed_status_ref[state]="${line#"${line%%[![:space:]]*}"}"
    parsed_status_ref[state]="${parsed_status_ref[state],,}"
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      case "${line}" in
        Relay:*)
          [[ -z "${parsed_status_ref[relay]}" ]] || continue
          value="${line#Relay:}"
          value="${value#"${value%%[! ]*}"}"
          parsed_status_ref[relay]="${value%%:*}"
          ;;
        "Visible location:"*)
          value="${line#Visible location:}"
          value="${value#"${value%%[![:space:]]*}"}"
          [[ -n "${parsed_status_ref[location]}" || "${value}" != ?*". IPv4:"* ]] || parsed_status_ref[location]="${value%. IPv4:*}"
          [[ -z "${parsed_status_ref[ipv4]}" ]] || continue
          read -ra fields <<<"${line}"
          for field_index in "${!fields[@]}"; do
            [[ "${fields[field_index]}" == IPv4: ]] || continue
            parsed_status_ref[ipv4]="${fields[field_index + 1]:-}"
            break
          done
          ;;
        IPv4:*)
          [[ -z "${parsed_status_ref[ipv4]}" ]] || continue
          read -ra fields <<<"${line}"
          parsed_status_ref[ipv4]="${fields[1]:-}"
          ;;
      esac
    done
  } <<<"$2"
}
