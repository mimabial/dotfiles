#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/install/lib/pam-authentication.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell install/fido2 [--remove]
Set up (or remove) FIDO2 hardware-key authentication for PAM." "$@"

FIDO2_AUTHFILE=/etc/fido2/fido2

check_fido2_hardware() {
  local detected_tokens=""
  detected_tokens="$(fido2-token -L 2>/dev/null)"
  if [[ -z "${detected_tokens}" ]]; then
    print_auth_error "\nNo FIDO2 device detected. Please plug it in (you may need to unlock it as well)."
    return 1
  fi
  return 0
}

if [[ "--remove" == "${1:-}" ]]; then
  print_auth_success "Removing FIDO2 device from authentication.\n"

  remove_pam_authentication "FIDO2" "pam_u2f.so"

  if [[ -d "${FIDO2_AUTHFILE%/*}" ]]; then
    print_auth_info "Removing FIDO2 configuration..."
    sudo rm -rf "${FIDO2_AUTHFILE%/*}"
  fi

  print_auth_info "Removing FIDO2 packages..."
  hyprshell pm --noconfirm remove libfido2 pam-u2f

  print_auth_success "FIDO2 authentication has been completely removed."
else
  print_auth_success "Setting up FIDO2 device for authentication.\n"

  print_auth_info "Installing required packages..."
  hyprshell pm add libfido2 pam-u2f

  if ! check_fido2_hardware; then
    exit 1
  fi

  if [[ ! -f "${FIDO2_AUTHFILE}" ]]; then
    sudo mkdir -p "${FIDO2_AUTHFILE%/*}"
    print_auth_success "\nLet's setup your device by confirming on the device now."
    print_auth_info "Touch your FIDO2 key when it lights up...\n"

    registration="$(mktemp)"
    if pamu2fcfg >"${registration}"; then
      sudo mv "${registration}" "${FIDO2_AUTHFILE}"
      print_auth_success "FIDO2 device registered successfully!"
    else
      rm -f -- "${registration}"
      print_auth_error "\nFIDO2 registration failed. Please try again."
      exit 1
    fi
  else
    print_auth_info "FIDO2 device already registered."
  fi

  configure_pam_authentication "FIDO2" "pam_u2f.so" "cue authfile=${FIDO2_AUTHFILE}"

  print_auth_info "\nTesting FIDO2 authentication with sudo..."
  print_auth_info "Touch your FIDO2 key when prompted.\n"

  if sudo echo "FIDO2 authentication test successful"; then
    print_auth_success "\nPerfect! FIDO2 authentication is now configured."
    print_auth_info "You can use your FIDO2 key for sudo and polkit authentication."
  else
    print_auth_error "\nVerification failed. You may want to check your configuration."
  fi
fi
