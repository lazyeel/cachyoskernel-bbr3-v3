#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (e.g. sudo ./install.sh)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER=$(cat "${SCRIPT_DIR}/kver")

echo "==> Installing CachyOS Server Kernel with BBRv3 (${KVER})..."

# 1. Copy Kernel bzImage
echo "==> Copying kernel image to /boot/vmlinuz-${KVER}..."
cp -f "${SCRIPT_DIR}/bzImage" "/boot/vmlinuz-${KVER}"

# 2. Copy System.map & Config (if present)
[ -f "${SCRIPT_DIR}/System.map" ] && cp -f "${SCRIPT_DIR}/System.map" "/boot/System.map-${KVER}"
[ -f "${SCRIPT_DIR}/config" ] && cp -f "${SCRIPT_DIR}/config" "/boot/config-${KVER}"

# 3. Copy Modules
echo "==> Installing kernel modules to /lib/modules/${KVER}..."
mkdir -p "/lib/modules/${KVER}"
cp -rf "${SCRIPT_DIR}/modules/"* "/lib/modules/${KVER}/"

# 4. Generate Module Dependencies
echo "==> Running depmod..."
depmod -a "${KVER}"

# 5. Generate Initramfs (Distribution auto-detection)
echo "==> Generating initramfs..."
if command -v update-initramfs >/dev/null 2>&1; then
    echo "    Detected Debian/Ubuntu (update-initramfs)"
    update-initramfs -c -k "${KVER}"
elif command -v mkinitcpio >/dev/null 2>&1; then
    echo "    Detected Arch Linux (mkinitcpio)"
    mkinitcpio -k "${KVER}" -g "/boot/initramfs-${KVER}.img"
elif command -v dracut >/dev/null 2>&1; then
    echo "    Detected Fedora/RHEL/Generic (dracut)"
    dracut --force "/boot/initramfs-${KVER}.img" "${KVER}"
else
    echo "WARNING: No known initramfs generator found. Please generate initramfs manually!" >&2
fi

# 6. Update Bootloader
echo "==> Updating bootloader..."
if command -v update-grub >/dev/null 2>&1; then
    update-grub
elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig >/dev/null 2>&1; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
elif command -v bootctl >/dev/null 2>&1; then
    echo "    systemd-boot detected. Please add an entry for /boot/vmlinuz-${KVER} if needed."
fi

echo "==> Installation complete! You can now reboot into ${KVER}."
