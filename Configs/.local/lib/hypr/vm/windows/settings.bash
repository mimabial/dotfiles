XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
WINDOWS_CONFIG_DIR="${XDG_CONFIG_HOME}/windows"
WINDOWS_COMPOSE_PATH="${WINDOWS_CONFIG_DIR}/docker-compose.yml"
WINDOWS_DATA_DIR="$HOME/.windows"
WINDOWS_SHARE_DIR="$HOME/Windows"
WINDOWS_APPLICATIONS_DIR="${XDG_DATA_HOME}/applications"
WINDOWS_ICON_DIR="$WINDOWS_APPLICATIONS_DIR/icons"
WINDOWS_DESKTOP_FILE="$WINDOWS_APPLICATIONS_DIR/windows-vm.desktop"
WINDOWS_CONTAINER_NAME="hypr-windows"
WINDOWS_CONTAINER_IMAGE="dockurr/windows"
WINDOWS_VERSION=11
WINDOWS_WEB_PORT=8006
WINDOWS_WEB_UI_URL="http://127.0.0.1:${WINDOWS_WEB_PORT}"
WINDOWS_RDP_HOST=127.0.0.1
WINDOWS_RDP_PORT=3389
WINDOWS_RDP_ADDRESS="${WINDOWS_RDP_HOST}:${WINDOWS_RDP_PORT}"
WINDOWS_DEFAULT_USERNAME=docker
WINDOWS_DEFAULT_PASSWORD="admin"
WINDOWS_STOP_GRACE_PERIOD=2m
WINDOWS_BOX_WIDTH=36

windows_print_box() {
  local rule="" row=""
  printf -v rule '%*s' "${WINDOWS_BOX_WIDTH}" ''
  rule="${rule// /═}"
  printf '╔%s╗\n' "${rule}"
  printf '║  %-*s║\n' "$((WINDOWS_BOX_WIDTH - 2))" "$1"
  printf '╠%s╣\n' "${rule}"
  for row in "${@:2}"; do
    printf '║  %-*s║\n' "$((WINDOWS_BOX_WIDTH - 2))" "${row}"
  done
  printf '╚%s╝\n' "${rule}"
}
