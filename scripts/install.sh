#!/usr/bin/env bash
# Remote NixOS installation over SSH
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "${REPO_ROOT}"

info "Remote NixOS installation for ${HOST}"
echo ""
echo "Prerequisites:"
echo "  1. Device is booted from the installer (./deploy build-iso or ./deploy netboot)"
echo "  2. Device is on the network"
echo ""

check_ssh

# Detect storage devices
info "Detecting storage devices on ${HOST}..."
ssh ${SSH_OPTS} "$TARGET" "lsblk -d -o NAME,SIZE,TYPE,MODEL" || true
echo ""
read -p "Enter target device for installation (e.g., /dev/nvme0n1, /dev/sda): " TARGET_DEVICE

if [[ -z "$TARGET_DEVICE" ]]; then
    error "No device specified."
    exit 1
fi

warn "ALL DATA ON ${TARGET_DEVICE} WILL BE ERASED!"
read -p "Are you sure? [y/N] " -n 1 -r
echo ""
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }

# Partition and format
info "Partitioning ${TARGET_DEVICE}..."
ssh ${SSH_OPTS} "$TARGET" "sudo bash -s" << PARTITION_EOF
set -euo pipefail
sgdisk --zap-all "${TARGET_DEVICE}"
partprobe "${TARGET_DEVICE}"
udevadm settle
sleep 2

sgdisk --new=1:8196:+512M --typecode=1:ef00 --change-name=1:"EFI" "${TARGET_DEVICE}"
sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Root" "${TARGET_DEVICE}"
partprobe "${TARGET_DEVICE}"
udevadm settle
sleep 1

# Determine partition names
if [[ "${TARGET_DEVICE}" =~ [0-9]$ ]]; then
    PART1="${TARGET_DEVICE}p1"
    PART2="${TARGET_DEVICE}p2"
else
    PART1="${TARGET_DEVICE}1"
    PART2="${TARGET_DEVICE}2"
fi

echo "Formatting EFI partition (\$PART1)..."
mkfs.vfat -n "EFI" "\$PART1"

echo "Formatting root partition (\$PART2)..."
mkfs.ext4 -L "ROOT" "\$PART2"

echo "Mounting..."
mount "\$PART2" /mnt
mkdir -p /mnt/boot/efi
mount "\$PART1" /mnt/boot/efi

echo "Partitioning complete."
PARTITION_EOF

# Copy repo to device
info "Copying repository to ${HOST}:/mnt/etc/nixos/..."
ssh ${SSH_OPTS} "$TARGET" "sudo mkdir -p /mnt/etc/nixos"
rsync -az --exclude='.git' --exclude='result' --exclude='secrets/key.txt' --exclude='secrets/secrets.yaml.work' \
    -e "ssh ${SSH_OPTS}" \
    ./ "${TARGET}:/tmp/nixos-config/"
ssh ${SSH_OPTS} "$TARGET" "sudo cp -r /tmp/nixos-config/. /mnt/etc/nixos/ && rm -rf /tmp/nixos-config"

# Copy SOPS key
info "Setting up SOPS key..."
KEY_PATH=""
if [ -r "$(pwd)/secrets/key.txt" ]; then
    KEY_PATH="$(pwd)/secrets/key.txt"
elif [ -r /var/lib/sops-nix/key.txt ]; then
    KEY_PATH="/var/lib/sops-nix/key.txt"
else
    error "No SOPS age key found in secrets/key.txt or /var/lib/sops-nix/key.txt"
    echo "Run: cd secrets && ./encrypt"
    exit 1
fi
info "Using key: ${KEY_PATH}"
ssh ${SSH_OPTS} "$TARGET" "sudo mkdir -p /mnt/var/lib/sops-nix"
cat "${KEY_PATH}" | ssh ${SSH_OPTS} "$TARGET" "cat > /tmp/sops-key.txt"
ssh ${SSH_OPTS} "$TARGET" "sudo mv /tmp/sops-key.txt /mnt/var/lib/sops-nix/key.txt && sudo chmod 600 /mnt/var/lib/sops-nix/key.txt"

# Install NixOS
info "Installing NixOS from local flake..."
ssh -t ${SSH_OPTS} "$TARGET" "sudo nixos-install --flake /mnt/etc/nixos#${HOST} --no-channel-copy --no-root-password"

# Unmount
info "Unmounting..."
ssh ${SSH_OPTS} "$TARGET" "sudo umount /mnt/boot/efi; sudo umount /mnt" || true

echo ""
info "Installation complete!"
echo "Reboot the device:"
echo "  ssh ${TARGET} 'sudo reboot'"
echo ""
echo "After reboot, connect with:"
echo "  ./deploy ssh"
