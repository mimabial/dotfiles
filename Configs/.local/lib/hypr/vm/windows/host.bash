WINDOWS_IMAGE_RESERVE_GB=10
WINDOWS_DISK_SIZES_GB=(32 64 128 256 512)
WINDOWS_DEFAULT_DISK_GB=64
WINDOWS_RAM_SIZES_GB=(2 4 8 16 32 64)
WINDOWS_DEFAULT_RAM_GB=4
WINDOWS_DEFAULT_CPU_CORES=2

windows_require_host_capacity() {
  local disk_size_gb=${1:-${WINDOWS_DEFAULT_DISK_GB}}
  local required_space=$((disk_size_gb + WINDOWS_IMAGE_RESERVE_GB))
  local available_space

  if [ ! -e /dev/kvm ]; then
    echo "❌ KVM virtualization not available!"
    echo ""
    echo "Please enable virtualization in BIOS or run:"
    echo "  sudo modprobe kvm-intel  # for Intel CPUs"
    echo "  sudo modprobe kvm-amd    # for AMD CPUs"
    dunstify -u critical -t "${NOTIFY_ERROR_MS}" -i "computer" "Windows VM" "KVM virtualization not available"
    exit 1
  fi

  available_space=$(windows_available_storage_gb)
  if [ "$available_space" -lt "$required_space" ]; then
    echo "❌ Insufficient disk space!"
    echo "   Available: ${available_space}GB"
    echo "   Required: ${required_space}GB (${disk_size_gb}GB disk + ${WINDOWS_IMAGE_RESERVE_GB}GB for Windows image)"
    exit 1
  fi
}

windows_available_storage_gb() {
  df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}'
}

windows_read_host_resources() {
  local -n host_resources="$1"
  host_resources[memory_label]=$(free -h | awk 'NR==2 {print $2}')
  host_resources[memory_gb]=$(awk 'NR==1 {printf "%d", $2/1024/1024}' /proc/meminfo)
  host_resources[cpu_cores]=$(nproc)
}

windows_show_host_resources() {
  local -n host_resources="$1"
  echo ""
  echo "System Resources Detected:"
  echo "  Total RAM: ${host_resources[memory_label]}"
  echo "  Total CPU Cores: ${host_resources[cpu_cores]}"
  echo ""
}

windows_gigabyte_size_choices() {
  local limit="$1" size options=""
  shift
  for size in "$@"; do
    ((size <= limit)) && options+=" ${size}G"
  done
  printf '%s' "${options}"
}
