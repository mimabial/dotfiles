#!/usr/bin/env bash
#|---/ /+----------------------------------+---/ /|#
#|--/ /-| Bootloader install (Limine)     |--/ /-|#
#|/ /---+----------------------------------+/ /---|#

scrDir=$(dirname "$(realpath "$0")")
# shellcheck disable=SC1091
if ! source "${scrDir}/global_fn.sh"; then
    echo "Error: unable to source global_fn.sh..."
    exit 1
fi

flg_DryRun=${flg_DryRun:-0}
BOOTLOADER=${BOOTLOADER:-}
BOOTLOADER_REMOVABLE=${BOOTLOADER_REMOVABLE:-false}

SUDO=""
if [ "${EUID}" -ne 0 ]; then
    SUDO="sudo"
fi

ask_install() {
    prompt_timer 120 "Install Limine bootloader now? [y/N]"
    case "${PROMPT_INPUT}" in
    y | Y) return 0 ;;
    *)
        print_log -sec "bootloader" -stat "skip" "limine install skipped"
        return 1
        ;;
    esac
}

ensure_pkg() {
    local pkg="$1"
    if pkg_installed "${pkg}"; then
        return 0
    fi
    if [ "${flg_DryRun}" -ne 1 ]; then
        ${SUDO} pacman -S --needed --noconfirm "${pkg}"
    else
        print_log -y "[dry-run] " -b "install" " ${pkg}"
    fi
}

if [[ "${BOOTLOADER}" != "limine" ]]; then
    ask_install || exit 0
fi

uefi=false
if [ -d /sys/firmware/efi ]; then
    uefi=true
fi

ensure_pkg limine
if [ "${uefi}" = true ]; then
    ensure_pkg efibootmgr
fi

# Detect ESP mountpoint (prefer /efi, then /boot/efi, then /boot)
esp_mount=""
for cand in /efi /boot/efi /boot; do
    if findmnt -no TARGET "${cand}" >/dev/null 2>&1; then
        fstype=$(findmnt -no FSTYPE "${cand}" 2>/dev/null || true)
        if [[ "${fstype}" == "vfat" || "${fstype}" == "fat" || "${fstype}" == "fat32" ]]; then
            esp_mount="${cand}"
            break
        fi
    fi
done

if [ -z "${esp_mount}" ]; then
    print_log -err "bootloader" "No EFI system partition (vfat) mounted at /efi, /boot/efi, or /boot"
    exit 1
fi

esp_dev=$(findmnt -no SOURCE "${esp_mount}" 2>/dev/null || true)
if [ -z "${esp_dev}" ]; then
    print_log -err "bootloader" "Unable to detect ESP device for ${esp_mount}"
    exit 1
fi

boot_mount="/boot"
if ! findmnt -no TARGET /boot >/dev/null 2>&1; then
    boot_mount="/"
fi
boot_dev=$(findmnt -no SOURCE "${boot_mount}" 2>/dev/null || true)
boot_partuuid=""
if [ -n "${boot_dev}" ]; then
    boot_partuuid=$(blkid -s PARTUUID -o value "${boot_dev}" 2>/dev/null || true)
fi

path_root="boot()"
if [ "${boot_mount}" != "${esp_mount}" ] && [ -n "${boot_partuuid}" ]; then
    path_root="uuid(${boot_partuuid})"
fi

if [ "${uefi}" = true ]; then
    if [ "${BOOTLOADER_REMOVABLE}" = "true" ]; then
        efi_dir="${esp_mount}/EFI/BOOT"
        loader_path='\EFI\BOOT\BOOTX64.EFI'
    else
        efi_dir="${esp_mount}/EFI/arch-limine"
        loader_path='\EFI\arch-limine\BOOTX64.EFI'
    fi

    if [ "${flg_DryRun}" -ne 1 ]; then
        ${SUDO} mkdir -p "${efi_dir}"
        ${SUDO} cp /usr/share/limine/BOOTIA32.EFI "${efi_dir}/" || true
        ${SUDO} cp /usr/share/limine/BOOTX64.EFI "${efi_dir}/"
    else
        print_log -y "[dry-run] " -b "copy" "limine EFI binaries to ${efi_dir}"
    fi

    if [ "${BOOTLOADER_REMOVABLE}" != "true" ]; then
        parent_dev=$(lsblk -no PKNAME "${esp_dev}" 2>/dev/null || true)
        partno=$(lsblk -no PARTNO "${esp_dev}" 2>/dev/null || true)
        if [ -n "${parent_dev}" ] && [ -n "${partno}" ]; then
            if [ "${flg_DryRun}" -ne 1 ]; then
                ${SUDO} efibootmgr --create --disk "/dev/${parent_dev}" --part "${partno}" --label "Arch Linux Limine Bootloader" --loader "${loader_path}" --unicode --verbose || true
            else
                print_log -y "[dry-run] " -b "efibootmgr" "--create --disk /dev/${parent_dev} --part ${partno} --label 'Arch Linux Limine Bootloader' --loader ${loader_path}"
            fi
        else
            print_log -warn "bootloader" "Unable to detect parent device/partition for efibootmgr; skipping EFI entry"
        fi
    fi

    hook_command="/usr/bin/cp /usr/share/limine/BOOTIA32.EFI ${efi_dir}/ && /usr/bin/cp /usr/share/limine/BOOTX64.EFI ${efi_dir}/"
    config_path="${efi_dir}/limine.conf"
else
    boot_limine_path="/boot/limine"
    if [ "${flg_DryRun}" -ne 1 ]; then
        ${SUDO} mkdir -p "${boot_limine_path}"
        ${SUDO} cp /usr/share/limine/limine-bios.sys "${boot_limine_path}/"
    else
        print_log -y "[dry-run] " -b "copy" "limine-bios.sys to ${boot_limine_path}"
    fi

    parent_dev=$(lsblk -no PKNAME "${boot_dev}" 2>/dev/null || true)
    if [ -n "${parent_dev}" ] && [ "${flg_DryRun}" -ne 1 ]; then
        ${SUDO} limine bios-install "/dev/${parent_dev}" || true
    fi

    hook_command="/usr/bin/limine bios-install /dev/${parent_dev} && /usr/bin/cp /usr/share/limine/limine-bios.sys /boot/limine/"
    config_path="${boot_limine_path}/limine.conf"
fi

# Pacman hook to redeploy limine on upgrade
hook_contents="[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = limine

[Action]
Description = Deploying Limine after upgrade...
When = PostTransaction
Exec = /bin/sh -c \"${hook_command}\"\n"

if [ "${flg_DryRun}" -ne 1 ]; then
    ${SUDO} mkdir -p /etc/pacman.d/hooks
    echo -e "${hook_contents}" | ${SUDO} tee /etc/pacman.d/hooks/99-limine.hook >/dev/null
else
    print_log -y "[dry-run] " -b "hook" "/etc/pacman.d/hooks/99-limine.hook"
fi

# Build limine.conf
kernel_params=$(cat /proc/cmdline | sed -E 's/(^| )BOOT_IMAGE=[^ ]+//g' | xargs || true)

kernels=()
for img in /boot/vmlinuz-*; do
    [ -e "${img}" ] && kernels+=("${img}")
done

if [ ${#kernels[@]} -eq 0 ]; then
    print_log -err "bootloader" "No kernels found in /boot (vmlinuz-*)"
    exit 1
fi

ucode_entries=""
for ucode in /boot/intel-ucode.img /boot/amd-ucode.img; do
    if [ -f "${ucode}" ]; then
        ucode_entries+="    module_path: ${path_root}:/${ucode##/boot/}\n"
    fi
done

config_contents="timeout: 5\n"

for img in "${kernels[@]}"; do
    kname=$(basename "${img}" | sed 's/^vmlinuz-//')
    initramfs="/boot/initramfs-${kname}.img"
    if [ ! -f "${initramfs}" ]; then
        initramfs="/boot/initramfs-${kname}-fallback.img"
    fi

    config_contents+="\n/Arch Linux (${kname})\n"
    config_contents+="    protocol: linux\n"
    config_contents+="    path: ${path_root}:/vmlinuz-${kname}\n"
    config_contents+="    cmdline: ${kernel_params}\n"
    if [ -n "${ucode_entries}" ]; then
        config_contents+="${ucode_entries}"
    fi
    if [ -f "${initramfs}" ]; then
        config_contents+="    module_path: ${path_root}:/${initramfs##/boot/}\n"
    fi

done

# Add Windows entry if detected on the ESP
windows_efi_path="${esp_mount}/EFI/Microsoft/Boot/bootmgfw.efi"
if [ -f "${windows_efi_path}" ]; then
    config_contents+="\n/Windows\n"
    config_contents+="    protocol: efi\n"
    if [ "${BOOTLOADER_REMOVABLE}" = "true" ]; then
        config_contents+="    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n"
    else
        config_contents+="    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n"
    fi
fi

if [ "${flg_DryRun}" -ne 1 ]; then
    echo -e "${config_contents}" | ${SUDO} tee "${config_path}" >/dev/null
    print_log -g "[bootloader] " -stat "limine" "Configured ${config_path}"
else
    print_log -y "[dry-run] " -b "config" "${config_path}"
fi
