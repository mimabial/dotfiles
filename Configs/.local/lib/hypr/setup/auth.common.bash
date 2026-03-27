#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
  echo -e "${GREEN}$1${NC}"
}

print_error() {
  echo -e "${RED}$1${NC}"
}

print_info() {
  echo -e "${YELLOW}$1${NC}"
}

setup_pam_module() {
  local auth_label="$1"
  local module_name="$2"
  local sudo_line="$3"
  local polkit_line="$4"

  if ! grep -Fq -- "${module_name}" /etc/pam.d/sudo; then
    print_info "Configuring sudo for ${auth_label} authentication..."
    sudo sed -i "1i ${sudo_line}" /etc/pam.d/sudo
  fi

  if [[ -f /etc/pam.d/polkit-1 ]]; then
    if ! grep -Fq -- "${module_name}" /etc/pam.d/polkit-1; then
      print_info "Configuring polkit for ${auth_label} authentication..."
      sudo sed -i "1i ${polkit_line}" /etc/pam.d/polkit-1
    fi
    return 0
  fi

  print_info "Creating polkit configuration with ${auth_label} authentication..."
  sudo tee /etc/pam.d/polkit-1 >/dev/null <<EOF
${polkit_line}
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
}

remove_pam_module() {
  local auth_label="$1"
  local module_name="$2"
  local module_regex="$3"

  if grep -Fq -- "${module_name}" /etc/pam.d/sudo; then
    print_info "Removing ${auth_label} authentication from sudo..."
    sudo sed -i "/${module_regex}/d" /etc/pam.d/sudo
  fi

  if [[ -f /etc/pam.d/polkit-1 ]] && grep -Fq -- "${module_name}" /etc/pam.d/polkit-1; then
    print_info "Removing ${auth_label} authentication from polkit..."
    sudo sed -i "/${module_regex}/d" /etc/pam.d/polkit-1
  fi
}
