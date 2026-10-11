windows_write_compose_config() {
  local -n installation_settings="$1"
  mkdir -p "$WINDOWS_SHARE_DIR"
  jq -n \
    --arg image "$WINDOWS_CONTAINER_IMAGE" --arg name "$WINDOWS_CONTAINER_NAME" \
    --arg version "$WINDOWS_VERSION" --arg grace_period "$WINDOWS_STOP_GRACE_PERIOD" \
    --arg ram "${installation_settings[ram_size]}" --arg cores "${installation_settings[cpu_cores]}" \
    --arg disk "${installation_settings[disk_size]}" \
    --arg username "${installation_settings[username]//\$/\$\$}" \
    --arg password "${installation_settings[password]//\$/\$\$}" \
    --arg storage "$WINDOWS_DATA_DIR" --arg shared "$WINDOWS_SHARE_DIR" \
    --arg web_port "$WINDOWS_WEB_PORT" --arg rdp_port "$WINDOWS_RDP_PORT" '
    {services: {windows: {
      image: $image, container_name: $name,
      environment: {VERSION: $version, RAM_SIZE: $ram, CPU_CORES: $cores, DISK_SIZE: $disk, USERNAME: $username, PASSWORD: $password},
      devices: ["/dev/kvm", "/dev/net/tun"], cap_add: ["NET_ADMIN"],
      ports: [$web_port + ":" + $web_port, $rdp_port + ":" + $rdp_port + "/tcp", $rdp_port + ":" + $rdp_port + "/udp"],
      volumes: [$storage + ":/storage", $shared + ":/shared"],
      restart: "always", stop_grace_period: $grace_period
    }}}' > "$WINDOWS_COMPOSE_PATH"
}

windows_read_credentials() {
  local -n credentials_ref="$1"
  local compose_config=""
  compose_config=$(docker-compose -f "$WINDOWS_COMPOSE_PATH" config --format json) || return 1
  {
    IFS= read -r -d '' 'credentials_ref[username]'
    IFS= read -r -d '' 'credentials_ref[password]'
  } < <(jq -jr '.services.windows.environment // {} | [(.USERNAME // ""), (.PASSWORD // "")][] | gsub("\\$\\$"; "$") + "\u0000"' <<<"$compose_config")
  credentials_ref[username]="${credentials_ref[username]:-$WINDOWS_DEFAULT_USERNAME}"
  credentials_ref[password]="${credentials_ref[password]:-$WINDOWS_DEFAULT_PASSWORD}"
}
