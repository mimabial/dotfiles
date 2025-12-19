#!/bin/bash
COMPOSE_FILE="$HOME/.config/windows/docker-compose.yml"

check_prerequisites() {
  local DISK_SIZE_GB=${1:-64}
  local REQUIRED_SPACE=$((DISK_SIZE_GB + 10))  # Add 10GB for Windows ISO and overhead

  # Check for KVM support
  if [ ! -e /dev/kvm ]; then
    echo "❌ KVM virtualization not available!"
    echo ""
    echo "Please enable virtualization in BIOS or run:"
    echo "  sudo modprobe kvm-intel  # for Intel CPUs"
    echo "  sudo modprobe kvm-amd    # for AMD CPUs"
    notify-send -u critical "Windows VM" "KVM virtualization not available"
    exit 1
  fi

  # Check disk space
  AVAILABLE_SPACE=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
  if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    echo "❌ Insufficient disk space!"
    echo "   Available: ${AVAILABLE_SPACE}GB"
    echo "   Required: ${REQUIRED_SPACE}GB (${DISK_SIZE_GB}GB disk + 10GB for Windows image)"
    exit 1
  fi
}

install_windows() {
  # Set up trap to handle Ctrl+C
  trap "echo ''; echo 'Installation cancelled by user'; exit 1" INT

  check_prerequisites

  hyprshell pkg/add.sh freerdp openbsd-netcat gum

  mkdir -p "$HOME/.windows"
  mkdir -p "$HOME/.config/windows"
  mkdir -p "$HOME/.local/share/applications/icons"

  # Install Windows VM icon and desktop file
  # Optional icon (skip if not present)
  if [ -f "$HOME/.local/share/icons/windows.png" ]; then
    cp "$HOME/.local/share/icons/windows.png" "$HOME/.local/share/applications/icons/windows.png"
  fi

  cat << EOF | tee "$HOME/.local/share/applications/windows-vm.desktop" > /dev/null
[Desktop Entry]
Name=Windows
Comment=Start Windows VM via Docker and connect with RDP
Exec=uwsm app -- hyprshell vm/windows.sh launch
Icon=$HOME/.local/share/applications/icons/windows.png
Terminal=false
Type=Application
Categories=System;Virtualization;
EOF

  # Get system resources
  TOTAL_RAM=$(free -h | awk 'NR==2 {print $2}')
  TOTAL_RAM_GB=$(awk 'NR==1 {printf "%d", $2/1024/1024}' /proc/meminfo)
  TOTAL_CORES=$(nproc)

  echo ""
  echo "System Resources Detected:"
  echo "  Total RAM: $TOTAL_RAM"
  echo "  Total CPU Cores: $TOTAL_CORES"
  echo ""

  RAM_OPTIONS=""
  for size in 2 4 8 16 32 64; do
    if [ $size -le $TOTAL_RAM_GB ]; then
      RAM_OPTIONS="$RAM_OPTIONS ${size}G"
    fi
  done

  SELECTED_RAM=$(echo $RAM_OPTIONS | tr ' ' '\n' | fzf --prompt="Select RAM > " --header="How much RAM for Windows VM?" --reverse --select-1 --query="4G")

  # Check if user cancelled
  if [ -z "$SELECTED_RAM" ]; then
    echo "Installation cancelled by user"
    exit 1
  fi

  read -p "Number of CPU cores (1-$TOTAL_CORES) [default: 2]: " SELECTED_CORES
  SELECTED_CORES=${SELECTED_CORES:-2}

  # Check if user cancelled (Ctrl+C)
  if [ -z "$SELECTED_CORES" ]; then
    echo "Installation cancelled by user"
    exit 1
  fi

  if ! [[ "$SELECTED_CORES" =~ ^[0-9]+$ ]] || [ "$SELECTED_CORES" -lt 1 ] || [ "$SELECTED_CORES" -gt "$TOTAL_CORES" ]; then
    echo "Invalid input. Using default: 2 cores"
    SELECTED_CORES=2
  fi

  AVAILABLE_SPACE=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
  MAX_DISK_GB=$((AVAILABLE_SPACE - 10))  # Leave 10GB for Windows image

  # Check if we have enough space for minimum
  if [ $MAX_DISK_GB -lt 32 ]; then
    echo "❌ Insufficient disk space for Windows VM!"
    echo "   Available: ${AVAILABLE_SPACE}GB"
    echo "   Minimum required: 42GB (32GB disk + 10GB for Windows image)"
    exit 1
  fi

  DISK_OPTIONS=""
  for size in 32 64 128 256 512; do
    if [ $size -le $MAX_DISK_GB ]; then
      DISK_OPTIONS="$DISK_OPTIONS ${size}G"
    fi
  done

  # Default to 64G if available, otherwise 32G
  DEFAULT_DISK="64G"
  if ! echo "$DISK_OPTIONS" | grep -q "64G"; then
    DEFAULT_DISK="32G"
  fi

  SELECTED_DISK=$(echo $DISK_OPTIONS | tr ' ' '\n' | fzf --prompt="Select Disk Size > " --header="Disk space for Windows VM (64GB+ recommended)" --reverse --select-1 --query="$DEFAULT_DISK")

  # Check if user cancelled
  if [ -z "$SELECTED_DISK" ]; then
    echo "Installation cancelled by user"
    exit 1
  fi

  # Extract just the number for prerequisite check
  DISK_SIZE_NUM=$(echo "$SELECTED_DISK" | sed 's/G//')

  # Re-check prerequisites with selected disk size
  check_prerequisites "$DISK_SIZE_NUM"

  # Prompt for username and password
  read -p "Windows username [default: docker]: " USERNAME
  USERNAME=${USERNAME:-docker}

  read -sp "Windows password [default: admin]: " PASSWORD
  echo
  if [ -z "$PASSWORD" ]; then
    PASSWORD="admin"
    PASSWORD_DISPLAY="(default)"
  else
    PASSWORD_DISPLAY="(user-defined)"
  fi

  # Display configuration summary
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

  # Ask for confirmation
  echo ""
  read -p "Proceed with this configuration? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled by user"
    exit 1
  fi

  mkdir -p $HOME/Windows

  # Create docker-compose.yml in user config directory
  cat << EOF | tee "$COMPOSE_FILE" > /dev/null
services:
  windows:
    image: dockurr/windows
    container_name: hypr-windows
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
      - $HOME/.windows:/storage
      - $HOME/Windows:/shared
    restart: always
    stop_grace_period: 2m
EOF

  echo ""
  echo "Starting Windows VM installation..."
  echo "This will download a Windows 11 image (may take 10-15 minutes)."
  echo ""
  echo "Monitor installation progress at: http://127.0.0.1:8006"
  echo ""

  # Start docker-compose with user's config
  echo "Starting Windows VM with docker-compose..."
  if ! docker-compose -f "$COMPOSE_FILE" up -d 2>&1; then
    echo "❌ Failed to start Windows VM!"
    echo "   Common issues:"
    echo "   - Docker daemon not running: sudo systemctl start docker"
    echo "   - Port already in use: check if another VM is running"
    echo "   - Permission issues: make sure you're in the docker group"
    exit 1
  fi

  echo ""
  echo "Windows VM is starting up!"
  echo ""
  echo "Opening browser to monitor installation..."

  # Open browser to monitor installation
  sleep 3
  xdg-open "http://127.0.0.1:8006"

  echo ""
  echo "Installation is running in the background."
  echo "You can monitor progress at: http://127.0.0.1:8006"
  echo ""
  echo "Once finished, launch 'Windows' via Super + Space"
  echo ""
  echo "To stop the VM: hyprshell vm/windows.sh stop"
  echo "To change resources: ~/.config/windows/docker-compose.yml"
  echo ""
}

remove_windows() {
  echo "Removing Windows VM..."

  docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true

  docker rmi dockurr/windows 2>/dev/null || echo "Image already removed or not found"

  rm "$HOME/.local/share/applications/windows-vm.desktop"
  rm -rf "$HOME/.config/windows"
  rm -rf "$HOME/.windows"

  echo ""
  echo "Windows VM removal completed!"
}

launch_windows() {
  KEEP_ALIVE=false
  if [ "$1" = "--keep-alive" ] || [ "$1" = "-k" ]; then
    KEEP_ALIVE=true
  fi

  # Check if config exists
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Windows VM not configured. Please run: hyprshell vm/windows.sh install"
    exit 1
  fi

  # Check if container is already running
  CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' hypr-windows 2>/dev/null)

  if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "Starting Windows VM..."

    # Send desktop notification
    notify-send "    Starting Windows VM" "      This can take 15-30 seconds" -t 15000

    if ! docker-compose -f "$COMPOSE_FILE" up -d 2>&1; then
      echo "❌ Failed to start Windows VM!"
      echo "   Try checking: hyprshell vm/windows.sh status"
      echo "   View logs: docker logs hypr-windows"
      notify-send -u critical "Windows VM" "Failed to start Windows VM"
      exit 1
    fi

    # Wait for RDP to be ready
    echo "Waiting for Windows VM to be ready..."
    WAIT_COUNT=0
    while ! nc -z 127.0.0.1 3389 2>/dev/null; do
      sleep 2
      WAIT_COUNT=$((WAIT_COUNT + 1))
      if [ $WAIT_COUNT -gt 60 ]; then  # 2 minutes timeout
        echo "❌ Timeout waiting for RDP!"
        echo "   The VM might still be installing Windows."
        echo "   Check progress at: http://127.0.0.1:8006"
        exit 1
      fi
    done

    # Give it a moment more to fully initialize
    sleep 5
  fi

  # Extract credentials from compose file
  WIN_USER=$(grep "USERNAME:" "$COMPOSE_FILE" | sed 's/.*USERNAME: "\(.*\)"/\1/')
  WIN_PASS=$(grep "PASSWORD:" "$COMPOSE_FILE" | sed 's/.*PASSWORD: "\(.*\)"/\1/')

  # Use defaults if not found
  [ -z "$WIN_USER" ] && WIN_USER="docker"
  [ -z "$WIN_PASS" ] && WIN_PASS="admin"

  # Build the connection info
  if [ "$KEEP_ALIVE" = true ]; then
    LIFECYCLE="VM will keep running after RDP closes
To stop: hyprshell vm/windows.sh stop"
  else
    LIFECYCLE="VM will auto-stop when RDP closes"
  fi

  echo ""
  echo "════════════════════════════════════"
  echo "    Connecting to Windows VM"
  echo ""
  echo "    $LIFECYCLE"
  echo "════════════════════════════════════"
  echo ""

  # Detect display scale from Hyprland
  HYPR_SCALE=$(hyprctl monitors -j | jq -r '.[0].scale')
  SCALE_PERCENT=$(echo "$HYPR_SCALE" | awk '{print int($1 * 100)}')

  RDP_SCALE=""
  if [ "$SCALE_PERCENT" -ge 170 ]; then
    RDP_SCALE="/scale:180"
  elif [ "$SCALE_PERCENT" -ge 130 ]; then
    RDP_SCALE="/scale:140"
  fi
  # If scale is less than 130%, don't set any scale (use default 100)

  # Connect with RDP in fullscreen (auto-detects resolution)
  xfreerdp3 /u:"$WIN_USER" /p:"$WIN_PASS" /v:127.0.0.1:3389 -grab-keyboard /sound /microphone /cert:ignore /title:"Windows VM" /dynamic-resolution /gfx:AVC444 /floatbar:sticky:off,default:visible,show:fullscreen $RDP_SCALE

  # After RDP closes, stop the container unless --keep-alive was specified
  if [ "$KEEP_ALIVE" = false ]; then
    echo ""
    echo "RDP session closed. Stopping Windows VM..."
    docker-compose -f "$COMPOSE_FILE" down
    echo "Windows VM stopped."
  else
    echo ""
    echo "RDP session closed. Windows VM is still running."
    echo "To stop it: hyprshell vm/windows.sh stop"
  fi
}

stop_windows() {
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Windows VM not configured."
    exit 1
  fi

  echo "Stopping Windows VM..."
  docker-compose -f "$COMPOSE_FILE" down
  echo "Windows VM stopped."
}

status_windows() {
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Windows VM not configured."
    echo "To set up: hyprshell vm/windows.sh install"
    exit 1
  fi

  CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' hypr-windows 2>/dev/null)

  if [ -z "$CONTAINER_STATUS" ]; then
    echo "Windows VM container not found."
    echo "To start: hyprshell vm/windows.sh launch"
  elif [ "$CONTAINER_STATUS" = "running" ]; then
    echo "╔════════════════════════════════════╗"
    echo "║  Windows VM Status: RUNNING        ║"
    echo "╠════════════════════════════════════╣"
    echo "║                                    ║"
    echo "║  Web interface:                    ║"
    echo "║    http://127.0.0.1:8006           ║"
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
    echo "Windows VM is stopped (status: $CONTAINER_STATUS)"
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

# Main command dispatcher
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
