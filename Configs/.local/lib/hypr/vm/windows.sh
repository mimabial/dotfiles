#!/usr/bin/env bash

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
COMPOSE_FILE="${XDG_CONFIG_HOME}/windows/docker-compose.yml"
WINDOWS_DATA_DIR="$HOME/.windows"
WINDOWS_SHARE_DIR="$HOME/Windows"
WINDOWS_APP_DIR="${XDG_DATA_HOME}/applications"
WINDOWS_ICON_DIR="$WINDOWS_APP_DIR/icons"
WINDOWS_DESKTOP_FILE="$WINDOWS_APP_DIR/windows-vm.desktop"
WINDOWS_CONTAINER_NAME="hypr-windows"
WINDOWS_WEB_UI_URL="http://127.0.0.1:8006"
WINDOWS_RDP_HOST="127.0.0.1:3389"

check_prerequisites() {
  local disk_size_gb=${1:-64}
  local required_space=$((disk_size_gb + 10))
  local available_space

  if [ ! -e /dev/kvm ]; then
    echo "❌ KVM virtualization not available!"
    echo ""
    echo "Please enable virtualization in BIOS or run:"
    echo "  sudo modprobe kvm-intel  # for Intel CPUs"
    echo "  sudo modprobe kvm-amd    # for AMD CPUs"
    dunstify -u critical -t 4000 -i "computer" "Windows VM" "KVM virtualization not available"
    exit 1
  fi

  available_space=$(available_home_space_gb)
  if [ "$available_space" -lt "$required_space" ]; then
    echo "❌ Insufficient disk space!"
    echo "   Available: ${available_space}GB"
    echo "   Required: ${required_space}GB (${disk_size_gb}GB disk + 10GB for Windows image)"
    exit 1
  fi
}

available_home_space_gb() {
  df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}'
}

ensure_windows_directories() {
  mkdir -p "$WINDOWS_DATA_DIR" "${XDG_CONFIG_HOME}/windows" "$WINDOWS_ICON_DIR"
}

copy_windows_icon() {
  local source_icon="${XDG_DATA_HOME}/icons/windows.png"
  local target_icon="$WINDOWS_ICON_DIR/windows.png"

  [ -f "$source_icon" ] || return 0
  cp "$source_icon" "$target_icon"
}

write_windows_desktop_entry() {
  cat > "$WINDOWS_DESKTOP_FILE" <<EOF2
[Desktop Entry]
Name=Windows
Comment=Start Windows VM via Docker and connect with RDP
Exec=uwsm app -- hyprshell vm/windows.sh launch
Icon=$WINDOWS_ICON_DIR/windows.png
Terminal=false
Type=Application
Categories=System;Virtualization;
EOF2
}

install_desktop_assets() {
  copy_windows_icon
  write_windows_desktop_entry
}

load_system_resources() {
  TOTAL_RAM=$(free -h | awk 'NR==2 {print $2}')
  TOTAL_RAM_GB=$(awk 'NR==1 {printf "%d", $2/1024/1024}' /proc/meminfo)
  TOTAL_CORES=$(nproc)
}

show_system_resources() {
  echo ""
  echo "System Resources Detected:"
  echo "  Total RAM: $TOTAL_RAM"
  echo "  Total CPU Cores: $TOTAL_CORES"
  echo ""
}

build_ram_options() {
  local size
  RAM_OPTIONS=""
  for size in 2 4 8 16 32 64; do
    if [ "$size" -le "$TOTAL_RAM_GB" ]; then
      RAM_OPTIONS="$RAM_OPTIONS ${size}G"
    fi
  done
}

prompt_fzf_choice() {
  local options="$1"
  local prompt="$2"
  local header="$3"
  local query="$4"

  echo "$options" | tr ' ' '\n' | fzf --prompt="$prompt" --header="$header" --reverse --select-1 --query="$query"
}

prompt_ram_selection() {
  build_ram_options
  SELECTED_RAM=$(prompt_fzf_choice "$RAM_OPTIONS" "Select RAM > " "How much RAM for Windows VM?" "4G")
  [ -n "$SELECTED_RAM" ] || cancel_install
}

cancel_install() {
  echo "Installation cancelled by user"
  exit 1
}

prompt_cpu_selection() {
  read -r -p "Number of CPU cores (1-$TOTAL_CORES) [default: 2]: " SELECTED_CORES
  SELECTED_CORES=${SELECTED_CORES:-2}

  if ! [[ "$SELECTED_CORES" =~ ^[0-9]+$ ]] || [ "$SELECTED_CORES" -lt 1 ] || [ "$SELECTED_CORES" -gt "$TOTAL_CORES" ]; then
    echo "Invalid input. Using default: 2 cores"
    SELECTED_CORES=2
  fi
}

build_disk_options() {
  local size
  local available_space

  available_space=$(available_home_space_gb)
  MAX_DISK_GB=$((available_space - 10))
  if [ "$MAX_DISK_GB" -lt 32 ]; then
    echo "❌ Insufficient disk space for Windows VM!"
    echo "   Available: ${available_space}GB"
    echo "   Minimum required: 42GB (32GB disk + 10GB for Windows image)"
    exit 1
  fi

  DISK_OPTIONS=""
  for size in 32 64 128 256 512; do
    if [ "$size" -le "$MAX_DISK_GB" ]; then
      DISK_OPTIONS="$DISK_OPTIONS ${size}G"
    fi
  done

  DEFAULT_DISK="64G"
  echo "$DISK_OPTIONS" | grep -q "64G" || DEFAULT_DISK="32G"
}

prompt_disk_selection() {
  build_disk_options
  SELECTED_DISK=$(prompt_fzf_choice "$DISK_OPTIONS" "Select Disk Size > " "Disk space for Windows VM (64GB+ recommended)" "$DEFAULT_DISK")
  [ -n "$SELECTED_DISK" ] || cancel_install

  DISK_SIZE_NUM=${SELECTED_DISK%G}
  check_prerequisites "$DISK_SIZE_NUM"
}

prompt_windows_credentials() {
  read -r -p "Windows username [default: docker]: " USERNAME
  USERNAME=${USERNAME:-docker}

  read -r -s -p "Windows password [default: admin]: " PASSWORD
  echo
  if [ -z "$PASSWORD" ]; then
    PASSWORD="admin"
    PASSWORD_DISPLAY="(default)"
  else
    PASSWORD_DISPLAY="(user-defined)"
  fi
}

show_install_summary() {
  echo ""
  echo "╔════════════════════════════════════╗"
  echo "║   Windows VM Configuration         ║"
  echo "╠════════════════════════════════════╣"
  echo "║                                    ║"
  echo "║  RAM:       $SELECTED_RAM                      ║"
  echo "║  CPU:       $SELECTED_CORES cores                   ║"
  echo "║  Disk:      $SELECTED_DISK                     ║"
  echo "║  Username:  $USERNAME                   ║"
  echo "║  Password:  $PASSWORD_DISPLAY            ║"
  echo "║                                    ║"
  echo "╚════════════════════════════════════╝"
}

confirm_installation() {
  echo ""
  read -r -n 1 -p "Proceed with this configuration? (y/N): " REPLY
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || cancel_install
}

write_compose_file() {
  mkdir -p "$WINDOWS_SHARE_DIR"
  cat > "$COMPOSE_FILE" <<EOF2
services:
  windows:
    image: dockurr/windows
    container_name: $WINDOWS_CONTAINER_NAME
    environment:
      VERSION: "11"
      RAM_SIZE: "$SELECTED_RAM"
      CPU_CORES: "$SELECTED_CORES"
      DISK_SIZE: "$SELECTED_DISK"
      USERNAME: "$USERNAME"
      PASSWORD: "$PASSWORD"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
      - 3389:3389/tcp
      - 3389:3389/udp
    volumes:
      - $WINDOWS_DATA_DIR:/storage
      - $WINDOWS_SHARE_DIR:/shared
    restart: always
    stop_grace_period: 2m
EOF2
}

docker_compose_up() {
  docker-compose -f "$COMPOSE_FILE" up -d
}

docker_compose_down() {
  docker-compose -f "$COMPOSE_FILE" down
}

start_windows_installation() {
  echo ""
  echo "Starting Windows VM installation..."
  echo "This will download a Windows 11 image (may take 10-15 minutes)."
  echo ""
  echo "Monitor installation progress at: $WINDOWS_WEB_UI_URL"
  echo ""
  echo "Starting Windows VM with docker-compose..."

  if ! docker_compose_up 2>&1; then
    echo "❌ Failed to start Windows VM!"
    echo "   Common issues:"
    echo "   - Docker daemon not running: sudo systemctl start docker"
    echo "   - Port already in use: check if another VM is running"
    echo "   - Permission issues: make sure you're in the docker group"
    exit 1
  fi
}

show_install_completion() {
  echo ""
  echo "Windows VM is starting up!"
  echo ""
  echo "Opening browser to monitor installation..."
  xdg-open "$WINDOWS_WEB_UI_URL"
  echo ""
  echo "Installation is running in the background."
  echo "You can monitor progress at: $WINDOWS_WEB_UI_URL"
  echo ""
  echo "Once finished, launch 'Windows' via Super + Space"
  echo ""
  echo "To stop the VM: hyprshell vm/windows.sh stop"
  echo "To change resources: $COMPOSE_FILE"
  echo ""
}

install_windows() {
  trap 'echo ""; echo "Installation cancelled by user"; exit 1' INT

  check_prerequisites
  hyprshell pm add freerdp openbsd-netcat gum
  ensure_windows_directories
  install_desktop_assets
  load_system_resources
  show_system_resources
  prompt_ram_selection
  prompt_cpu_selection
  prompt_disk_selection
  prompt_windows_credentials
  show_install_summary
  confirm_installation
  write_compose_file
  start_windows_installation
  show_install_completion
}

remove_windows() {
  echo "Removing Windows VM..."
  docker_compose_down 2>/dev/null || true
  docker rmi dockurr/windows 2>/dev/null || echo "Image already removed or not found"
  rm -f "$WINDOWS_DESKTOP_FILE"
  rm -rf "${XDG_CONFIG_HOME}/windows" "$WINDOWS_DATA_DIR"
  echo ""
  echo "Windows VM removal completed!"
}

parse_launch_mode() {
  KEEP_ALIVE=false
  if [ "${1:-}" = "--keep-alive" ] || [ "${1:-}" = "-k" ]; then
    KEEP_ALIVE=true
  fi
}

require_vm_config() {
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Windows VM not configured. Please run: hyprshell vm/windows.sh install"
    exit 1
  fi
}

windows_container_status() {
  docker inspect --format='{{.State.Status}}' "$WINDOWS_CONTAINER_NAME" 2>/dev/null
}

notify_vm_starting() {
  dunstify -r 42 -i "computer" "Windows VM" "Starting Windows VM\nThis can take 15-30 seconds" -t 0
}

notify_vm_start_failed() {
  dunstify -r 42 -u critical -t 5000 -i "computer" "Windows VM" "Failed to start Windows VM"
}

notify_vm_ready() {
  dunstify -r 42 -t 2000 -i "computer" "Windows VM" "Windows VM is ready. Opening RDP session."
}

wait_for_rdp_ready() {
  local wait_count=0
  local ready_streak=0

  echo "Waiting for Windows VM to be ready..."
  while (( ready_streak < 2 )); do
    if nc -z 127.0.0.1 3389 2>/dev/null; then
      ready_streak=$((ready_streak + 1))
      continue
    fi

    ready_streak=0
    sleep 2
    wait_count=$((wait_count + 1))
    if [ "$wait_count" -gt 60 ]; then
      echo "❌ Timeout waiting for RDP!"
      echo "   The VM might still be installing Windows."
      echo "   Check progress at: $WINDOWS_WEB_UI_URL"
      dunstify -r 42 -u critical -t 5000 -i "computer" "Windows VM" "Timed out waiting for RDP. The VM may still be installing."
      exit 1
    fi
  done
}

ensure_windows_vm_running() {
  local container_status

  container_status=$(windows_container_status)
  if [ "$container_status" = "running" ]; then
    return 0
  fi

  echo "Starting Windows VM..."
  notify_vm_starting
  if ! docker_compose_up 2>&1; then
    echo "❌ Failed to start Windows VM!"
    echo "   Try checking: hyprshell vm/windows.sh status"
    echo "   View logs: docker logs $WINDOWS_CONTAINER_NAME"
    notify_vm_start_failed
    exit 1
  fi

  wait_for_rdp_ready
  notify_vm_ready
}

load_windows_credentials() {
  WIN_USER=$(grep "USERNAME:" "$COMPOSE_FILE" | sed 's/.*USERNAME: "\(.*\)"/\1/')
  WIN_PASS=$(grep "PASSWORD:" "$COMPOSE_FILE" | sed 's/.*PASSWORD: "\(.*\)"/\1/')
  WIN_USER=${WIN_USER:-docker}
  WIN_PASS=${WIN_PASS:-admin}
}

rdp_lifecycle_message() {
  if [ "$KEEP_ALIVE" = true ]; then
    printf '%s\n%s' 'VM will keep running after RDP closes' 'To stop: hyprshell vm/windows.sh stop'
    return 0
  fi

  printf '%s' 'VM will auto-stop when RDP closes'
}

print_connection_banner() {
  echo ""
  echo "════════════════════════════════════"
  echo "    Connecting to Windows VM"
  echo ""
  echo "    $(rdp_lifecycle_message)"
  echo "════════════════════════════════════"
  echo ""
}

rdp_scale_flag() {
  local hypr_scale scale_percent

  hypr_scale=$(hyprctl monitors -j | jq -r '.[0].scale')
  scale_percent=$(echo "$hypr_scale" | awk '{print int($1 * 100)}')

  if [ "$scale_percent" -ge 170 ]; then
    echo "/scale:180"
  elif [ "$scale_percent" -ge 130 ]; then
    echo "/scale:140"
  fi
}

launch_rdp_session() {
  local scale_flag
  scale_flag=$(rdp_scale_flag)
  local -a rdp_args=(
    /u:"$WIN_USER"
    /p:"$WIN_PASS"
    /v:"$WINDOWS_RDP_HOST"
    "-grab-keyboard"
    "/sound"
    "/microphone"
    "/cert:ignore"
    /title:"Windows VM"
    "/dynamic-resolution"
    "/gfx:AVC444"
    "/floatbar:sticky:off,default:visible,show:fullscreen"
  )
  [[ -n "$scale_flag" ]] && rdp_args+=("$scale_flag")

  xfreerdp3 "${rdp_args[@]}"
}

handle_rdp_exit() {
  echo ""
  if [ "$KEEP_ALIVE" = true ]; then
    echo "RDP session closed. Windows VM is still running."
    echo "To stop it: hyprshell vm/windows.sh stop"
    return 0
  fi

  echo "RDP session closed. Stopping Windows VM..."
  docker_compose_down
  echo "Windows VM stopped."
}

launch_windows() {
  parse_launch_mode "$1"
  require_vm_config
  ensure_windows_vm_running
  load_windows_credentials
  print_connection_banner
  launch_rdp_session
  handle_rdp_exit
}

stop_windows() {
  require_vm_config
  echo "Stopping Windows VM..."
  docker_compose_down
  echo "Windows VM stopped."
}

status_windows() {
  local container_status

  require_vm_config
  container_status=$(windows_container_status)

  if [ -z "$container_status" ]; then
    echo "Windows VM container not found."
    echo "To start: hyprshell vm/windows.sh launch"
  elif [ "$container_status" = "running" ]; then
    echo "╔════════════════════════════════════╗"
    echo "║  Windows VM Status: RUNNING        ║"
    echo "╠════════════════════════════════════╣"
    echo "║                                    ║"
    echo "║  Web interface:                    ║"
    echo "║    $WINDOWS_WEB_UI_URL           ║"
    echo "║                                    ║"
    echo "║  RDP available: port 3389          ║"
    echo "║                                    ║"
    echo "║  To connect:                       ║"
    echo "║    hyprshell vm/windows.sh launch       ║"
    echo "║                                    ║"
    echo "║  To stop:                          ║"
    echo "║    hyprshell vm/windows.sh stop         ║"
    echo "║                                    ║"
    echo "╚════════════════════════════════════╝"
  else
    echo "Windows VM is stopped (status: $container_status)"
    echo "To start: hyprshell vm/windows.sh launch"
  fi
}

show_usage() {
  echo "Usage: hyprshell vm/windows.sh [command] [options]"
  echo ""
  echo "Commands:"
  echo "  install              Install and configure Windows VM"
  echo "  remove               Remove Windows VM and optionally its data"
  echo "  launch [options]     Start Windows VM (if needed) and connect via RDP"
  echo "                       Options:"
  echo "                         --keep-alive, -k   Keep VM running after RDP closes"
  echo "  stop                 Stop the running Windows VM"
  echo "  status               Show current VM status"
  echo "  help                 Show this help message"
  echo ""
  echo "Examples:"
  echo "  hyprshell vm/windows.sh install           # Set up Windows VM for first time"
  echo "  hyprshell vm/windows.sh launch            # Connect to VM (auto-stop on exit)"
  echo "  hyprshell vm/windows.sh launch -k         # Connect to VM (keep running)"
  echo "  hyprshell vm/windows.sh stop              # Shut down the VM"
}

case "$1" in
  install)
    install_windows
    ;;
  remove)
    remove_windows
    ;;
  launch|start)
    launch_windows "$2"
    ;;
  stop|down)
    stop_windows
    ;;
  status)
    status_windows
    ;;
  help|--help|-h|"")
    show_usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "" >&2
    show_usage >&2
    exit 1
    ;;
esac
