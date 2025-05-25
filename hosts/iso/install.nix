# Nix Installer Script Package

{ pkgs, lib, stdenv, fetchurl, settings, ... }:

stdenv.mkDerivation rec {
  pname = "nixinstall";
  version = "1.0.0";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/nixinstall << EOF
#!/usr/bin/env nix-shell
#!nix-shell -i bash -p parted git util-linux gptfdisk wget curl iw gptfdisk openssh --extra-experimental-features "flakes nix-command"

# NixOS Installer

set -e

# Configuration variables directly injected
HOST_NAME="${settings.hostName}"
REPO_URL="${settings.repoUrl}"
DESCRIPTION="${settings.description}"
ADMIN_USER="${settings.adminUser}"

echo "Welcome to NixOS Installer for \$DESCRIPTION"

# Check if running as root
if [ "\$EUID" -ne 0 ]; then
  echo "This installer must be run as root. Please use sudo."
  exit 1
fi

# Check network connectivity
echo "Checking network connectivity..."
if ! ping -c 3 github.com >/dev/null 2>&1; then
  echo "Error: No network connectivity. Please ensure the network is configured and try again."
  exit 1
fi

# Detect target device
echo "Detecting storage devices..."
lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT || { echo "Failed to detect storage devices"; exit 1; }

echo "Please enter the target device for installation (e.g., /dev/sda, /dev/mmcblk0, /dev/nvme0n1):"
read TARGET_DEVICE

# Validate target device
if [ ! -b "\$TARGET_DEVICE" ]; then
  echo "Error: \$TARGET_DEVICE is not a valid block device."
  exit 1
fi

# Confirm with the user before proceeding
echo "WARNING: This will erase all data on \$TARGET_DEVICE. Are you sure? (y/N)"
read CONFIRM
if [ "\$CONFIRM" != "y" ] && [ "\$CONFIRM" != "Y" ]; then
  echo "Aborted by user."
  exit 1
fi

# Explicitly clear any existing partition tables
echo "Clearing existing partition tables..."
sgdisk --zap-all "\$TARGET_DEVICE" || { echo "Failed to clear partition tables"; exit 1; }
partprobe "\$TARGET_DEVICE"  # Notify kernel of changes immediately
udevadm settle  # Wait for udev to process
sleep 3  # Additional delay to ensure stability

# Verify device is ready before proceeding
echo "Verifying device readiness..."
while ! sgdisk -p "\$TARGET_DEVICE" >/dev/null 2>&1; do
  echo "Device not ready, waiting..."
  sleep 1
done

# Create GPT partition table
echo "Creating GPT partition table..."
# Partition 1: EFI, starts at sector 8196, size 512M
sgdisk --new=1:8196:+512M --typecode=1:ef00 --change-name=1:"EFI" "\$TARGET_DEVICE" || { echo "Failed to create EFI partition"; exit 1; }
sleep 1
# Partition 2: Root, starts after Partition 1, extends to end of device
sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Root" "\$TARGET_DEVICE" || { echo "Failed to create root partition"; exit 1; }
sleep 1

# Inform the kernel of partition changes
partprobe "\$TARGET_DEVICE"
udevadm settle

# Determine partition names
if [[ "\$TARGET_DEVICE" =~ [0-9]$ ]]; then
  PART1="\''${TARGET_DEVICE}p1"
  PART2="\''${TARGET_DEVICE}p2"
else
  PART1="\''${TARGET_DEVICE}1"
  PART2="\''${TARGET_DEVICE}2"
fi

# Check if partitions exist
if [ ! -b "\$PART1" ] || [ ! -b "\$PART2" ]; then
  echo "Error: Partitions not found. Please check the device and try again."
  exit 1
fi

# Format partitions
echo "Formatting EFI partition..."
mkfs.vfat -n "EFI" "\$PART1" || { echo "Failed to format EFI partition"; exit 1; }

echo "Formatting root partition..."
mkfs.ext4 -L "\$HOST_NAME-Root" "\$PART2" || { echo "Failed to format root partition"; exit 1; }

# Mount partitions
echo "Mounting partitions..."
mount "\$PART2" /mnt || { echo "Failed to mount root partition"; exit 1; }
mkdir -p /mnt/boot/efi || { echo "Failed to create EFI mount point"; exit 1; }
mount "\$PART1" /mnt/boot/efi || { echo "Failed to mount EFI partition"; exit 1; }

# Create home directory and set ownership
mkdir -p /mnt/home/\$ADMIN_USER/.dotfiles || { echo "Failed to create home directory"; exit 1; }
chown 1000:1000 /mnt/home/\$ADMIN_USER /mnt/home/\$ADMIN_USER/.dotfiles || { echo "Failed to set home directory ownership"; exit 1; }

# Clone repository to /tmp for build
echo "Cloning repository for build..."
git clone "\$REPO_URL" /tmp/nixos-config || { echo "Failed to clone repository"; exit 1; }

# Clone repository to user's home directory
echo "Cloning repository to ~/.dotfiles..."
git clone "\$REPO_URL" /mnt/home/\$ADMIN_USER/.dotfiles || { echo "Failed to clone repository to ~/.dotfiles"; exit 1; }
chown -R 1000:1000 /mnt/home/\$ADMIN_USER/.dotfiles || { echo "Failed to set .dotfiles ownership"; exit 1; }

# Ensure SOPS key directory exists and copy key
echo "Setting up SOPS key..."
mkdir -p /mnt/var/lib/sops-nix
cp /var/lib/sops-nix/key.txt /mnt/var/lib/sops-nix/key.txt
chmod 600 /mnt/var/lib/sops-nix/key.txt

# Build system with experimental features enabled
echo "Building NixOS system..."
cd /tmp/nixos-config
nix build .#nixosConfigurations.\$HOST_NAME.config.system.build.toplevel || { echo "Failed to build NixOS system"; exit 1; }

# Install system
echo "Installing system..."
nixos-install --root /mnt --system ./result --no-channel-copy || { echo "Failed to install NixOS"; exit 1; }

# Verify installation
echo "Verifying installation..."
if [ ! -f /mnt/etc/ssh/sshd_config ]; then
  echo "Error: SSH configuration not found in installed system."
  exit 1
fi

# Unmount with fallback
echo "Unmounting..."
umount /mnt/boot/efi || { umount -l /mnt/boot/efi; echo "Forced unmount of EFI partition"; }
umount /mnt || { um bleek "Forced unmount of root partition"; }

# Post-install verification: Attempt SSH connection (non-blocking)
echo "Verifying SSH connectivity..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \$ADMIN_USER@localhost "echo 'SSH connection successful'" || {
  echo "Warning: Could not verify SSH connectivity. Please check network and SSH configuration after reboot."
}

# Done
echo "Installation complete! Please remove the installation media and reboot."
EOF
    chmod +x $out/bin/nixinstall
  '';

  meta = with lib; {
    description = "NixOS installer script";
    platforms = platforms.linux;
  };
}