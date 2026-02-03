#!/usr/bin/env bash

# Check release
if [ ! -f /etc/arch-release ]; then
  exit 0
fi

# source variables
scrDir=$(dirname "$(realpath "$0")")
# shellcheck disable=SC1091
source "$scrDir/../globalcontrol.sh"
get_aurhlpr
export -f pkg_installed
fpk_exup="pkg_installed flatpak && flatpak update"
temp_file="$XDG_RUNTIME_DIR/hypr/update_info"
# shellcheck source=/dev/null
[ -f "$temp_file" ] && source "$temp_file"

# Trigger upgrade
if [ "$1" == "up" ]; then
  if [ -f "$temp_file" ]; then
    # refreshes the module so after you update it will reset to zero
    trap 'pkill -RTMIN+20 waybar' EXIT
    # Read info from env file
    while IFS="=" read -r key value; do
      case "$key" in
        OFFICIAL_UPDATES) official=$value ;;
        AUR_UPDATES) aur=$value ;;
        FLATPAK_UPDATES) flatpak=$value ;;
      esac
    done <"$temp_file"

    command="
        fastfetch
        printf '[Official] %-10s\n[AUR]      %-10s\n[Flatpak]  %-10s\n' '$official' '$aur' '$flatpak'
        "${aurhlpr}" -Syu
        $fpk_exup
        read -n 1 -p 'Press any key to continue...'
        "
    kitty --title systemupdate sh -c "${command}"
  else
    echo "No upgrade info found. Please run the script without parameters first."
  fi
  exit 0
fi

# Get detailed update information
temp_db=$(mktemp -d "${XDG_RUNTIME_DIR:-"/tmp"}/checkupdates_db_XXXXXX")
trap '[ -n "$temp_db" ] && rm -rf "$temp_db" 2>/dev/null' EXIT INT TERM

# Official updates with details
ofc_list=$(CHECKUPDATES_DB="$temp_db" checkupdates 2>/dev/null)
ofc=$(echo "$ofc_list" | grep -c '^')
[ -z "$ofc_list" ] && ofc=0

# AUR updates with details
aur_list=$(${aurhlpr} -Qua 2>/dev/null)
aur=$(echo "$aur_list" | grep -c '^')
[ -z "$aur_list" ] && aur=0

# Flatpak updates with details
if pkg_installed flatpak; then
  fpk_list=$(flatpak remote-ls --updates --columns=application,version,branch 2>/dev/null)
  fpk=$(echo "$fpk_list" | grep -c '^')
  [ -z "$fpk_list" ] && fpk=0
else
  fpk=0
  fpk_list=""
fi

# Calculate total available updates
upd=$((ofc + aur + fpk))

# Build tooltip content
build_tooltip() {
  local title="<b>${upd} Updates</b>\n  ${ofc} Official (Pacman)\n  ${aur} AUR (${aurhlpr^^})\n  ${fpk} Universal (Flatpak)"
  local content=""

  # Format official packages
  if [ $ofc -gt 0 ]; then
    content+="<b>PACMAN:</b>\n"
    while IFS= read -r line; do
      pkg=$(echo "$line" | awk '{print $1}')
      old_ver=$(echo "$line" | awk '{print $2}')
      new_ver=$(echo "$line" | awk '{print $4}')
      content+="  ${pkg}  ${old_ver} → ${new_ver}\n"
    done <<<"$ofc_list"
  fi

  # Format AUR packages
  if [ $aur -gt 0 ]; then
    [ $ofc -gt 0 ] && content+="\n"
    content+="<b>AUR:</b>\n"
    while IFS= read -r line; do
      pkg=$(echo "$line" | awk '{print $1}')
      old_ver=$(echo "$line" | awk '{print $2}')
      new_ver=$(echo "$line" | awk '{print $4}')
      content+="  ${pkg}  ${old_ver} → ${new_ver}\n"
    done <<<"$aur_list"
  fi

  # Format Flatpak packages
  if [ $fpk -gt 0 ]; then
    [ $((ofc + aur)) -gt 0 ] && content+="\n"
    content+="<b>FLATPAK:</b>\n"
    # Get current versions for flatpaks
    while IFS=$'\t' read -r app new_ver branch; do
      old_ver=$(flatpak info "$app" 2>/dev/null | grep "Version:" | awk '{print $2}')
      [ -z "$old_ver" ] && old_ver="installed"
      pkg_name=$(echo "$app" | rev | cut -d'.' -f1 | rev)
      content+="  ${pkg_name}  ${old_ver} → ${new_ver}\n"
    done <<<"$fpk_list"
  fi

  # Remove trailing newline and format for JSON
  content=$(echo -n "$content" | sed 's/$/\\n/g' | tr -d '\n' | sed 's/\\n$//')

  echo "${title}\\n\\n${content}"
}

# Prepare the upgrade info
upgrade_info=$(
  cat <<EOF
OFFICIAL_UPDATES=$ofc
AUR_UPDATES=$aur
FLATPAK_UPDATES=$fpk
EOF
)

# Save the upgrade info
echo "$upgrade_info" >"$temp_file"
# Show output
if [ $upd -eq 0 ]; then
  upd="" #Remove Icon completely
  echo "{\"text\":\"$upd\", \"tooltip\":\" Packages are up to date\"}"
else
  tooltip=$(build_tooltip)
  # Escape special characters for JSON
  tooltip=$(echo "$tooltip" | sed 's/"/\\"/g')
  echo "{\"text\":\"󰮯\", \"tooltip\":\"$tooltip\"}"
fi
