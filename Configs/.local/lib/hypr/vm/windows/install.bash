windows_choose_gigabyte_size() {
  local options="$1"
  local prompt="$2"
  local header="$3"
  local query="$4"

  echo "$options" | tr ' ' '\n' | fzf --prompt="$prompt" --header="$header" --reverse --select-1 --query="$query"
}

windows_cancel_installation() {
  echo "Installation cancelled by user"
  exit 1
}

windows_choose_ram() {
  local -n installation_settings="$1" host_resources="$2"
  local choices=""
  choices=$(windows_gigabyte_size_choices "${host_resources[memory_gb]}" "${WINDOWS_RAM_SIZES_GB[@]}")
  installation_settings[ram_size]=$(windows_choose_gigabyte_size "$choices" "Select RAM > " "How much RAM for Windows VM?" "${WINDOWS_DEFAULT_RAM_GB}G")
  [[ -n "${installation_settings[ram_size]}" ]] || windows_cancel_installation
}

windows_choose_cpu_cores() {
  local -n installation_settings="$1" host_resources="$2"
  local default_cores="$WINDOWS_DEFAULT_CPU_CORES" selected_cores=""
  (( default_cores <= host_resources[cpu_cores] )) || default_cores="${host_resources[cpu_cores]}"
  read -r -p "Number of CPU cores (1-${host_resources[cpu_cores]}) [default: $default_cores]: " selected_cores
  selected_cores=${selected_cores:-$default_cores}
  if [[ ! "$selected_cores" =~ ^[0-9]+$ ]] || (( selected_cores < 1 || selected_cores > host_resources[cpu_cores] )); then
    echo "Invalid input. Using default: $default_cores cores"
    selected_cores="$default_cores"
  fi
  installation_settings[cpu_cores]="$selected_cores"
}

windows_choose_disk() {
  local -n installation_settings="$1"
  local available_gb maximum_gb minimum_gb="${WINDOWS_DISK_SIZES_GB[0]}" choices default_size
  available_gb=$(windows_available_storage_gb)
  maximum_gb=$((available_gb - WINDOWS_IMAGE_RESERVE_GB))
  if (( maximum_gb < minimum_gb )); then
    echo "❌ Insufficient disk space for Windows VM!"
    echo "   Available: ${available_gb}GB"
    echo "   Minimum required: $((minimum_gb + WINDOWS_IMAGE_RESERVE_GB))GB (${minimum_gb}GB disk + ${WINDOWS_IMAGE_RESERVE_GB}GB for Windows image)"
    exit 1
  fi
  choices=$(windows_gigabyte_size_choices "$maximum_gb" "${WINDOWS_DISK_SIZES_GB[@]}")
  default_size="${WINDOWS_DEFAULT_DISK_GB}G"
  [[ " $choices " == *" $default_size "* ]] || default_size="${minimum_gb}G"
  installation_settings[disk_size]=$(windows_choose_gigabyte_size "$choices" "Select Disk Size > " "Disk space for Windows VM (${WINDOWS_DEFAULT_DISK_GB}GB+ recommended)" "$default_size")
  [[ -n "${installation_settings[disk_size]}" ]] || windows_cancel_installation
  windows_require_host_capacity "${installation_settings[disk_size]%G}"
}

windows_choose_credentials() {
  local -n installation_settings="$1"
  read -r -p "Windows username [default: $WINDOWS_DEFAULT_USERNAME]: " 'installation_settings[username]'
  installation_settings[username]="${installation_settings[username]:-$WINDOWS_DEFAULT_USERNAME}"
  read -r -s -p "Windows password [default: $WINDOWS_DEFAULT_PASSWORD]: " 'installation_settings[password]'
  echo
  if [[ -z "${installation_settings[password]}" ]]; then
    installation_settings[password]="$WINDOWS_DEFAULT_PASSWORD"
    installation_settings[password_source]="(default)"
  else
    installation_settings[password_source]="(user-defined)"
  fi
}

windows_show_installation_settings() {
  local -n installation_settings="$1"
  echo ""
  windows_print_box "Windows VM Configuration" "" \
    "RAM:       ${installation_settings[ram_size]}" \
    "CPU:       ${installation_settings[cpu_cores]} cores" \
    "Disk:      ${installation_settings[disk_size]}" \
    "Username:  ${installation_settings[username]}" \
    "Password:  ${installation_settings[password_source]}" ""
}

windows_confirm_installation() {
  echo ""
  read -r -n 1 -p "Proceed with this configuration? (y/N): " REPLY
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || windows_cancel_installation
}

windows_start_installation() {
  echo ""
  echo "Starting Windows VM installation..."
  echo "This will download a Windows $WINDOWS_VERSION image (may take 10-15 minutes)."
  echo ""
  echo "Monitor installation progress at: $WINDOWS_WEB_UI_URL"
  echo ""
  echo "Starting Windows VM with docker-compose..."

  if ! windows_start_container 2>&1; then
    echo "❌ Failed to start Windows VM!"
    echo "   Common issues:"
    echo "   - Docker daemon not running: start your Docker service"
    echo "   - Port already in use: check if another VM is running"
    echo "   - Permission issues: make sure you're in the docker group"
    exit 1
  fi
}

windows_show_installation_started() {
  echo ""
  echo "Windows VM is starting up!"
  echo ""
  echo "Opening browser to monitor installation..."
  xdg-open "$WINDOWS_WEB_UI_URL"
  echo ""
  echo "Installation is running in the background."
  echo "You can monitor progress at: $WINDOWS_WEB_UI_URL"
  echo ""
  echo "Once finished, launch 'Windows' from the application finder (Super + D)"
  echo ""
  echo "To stop the VM: hyprshell vm/windows.sh stop"
  echo "To change resources: $WINDOWS_COMPOSE_PATH"
  echo ""
}

windows_install() {
  local -A installation=() host=()
  trap 'echo ""; echo "Installation cancelled by user"; exit 1' INT
  windows_require_host_capacity "${WINDOWS_DISK_SIZES_GB[0]}"
  "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/package-manager.sh" add freerdp openbsd-netcat fzf docker-compose jq
  windows_prepare_directories
  windows_install_desktop_assets
  windows_read_host_resources host
  windows_show_host_resources host
  windows_choose_ram installation host
  windows_choose_cpu_cores installation host
  windows_choose_disk installation
  windows_choose_credentials installation
  windows_show_installation_settings installation
  windows_confirm_installation
  windows_write_compose_config installation
  windows_start_installation
  windows_show_installation_started
}
