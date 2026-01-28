# Nix Installer Script Package

{
  lib,
  stdenv,
  settings,
  ...
}:

stdenv.mkDerivation {
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

    # Configuration from settings.nix
    HOST_NAME="${settings.hostName}"
    REPO_URL="${settings.repoUrl}"
    FLAKE_REF="github:${settings.repoUrl}"
    DESCRIPTION="${settings.description}"
    ADMIN_USER="${settings.adminUser}"

    echo "Welcome to NixOS Installer for \$DESCRIPTION"

    if [ "\$EUID" -ne 0 ]; then
      echo "This installer must be run as root. Please use sudo."
      exit 1
    fi

    echo "Checking network connectivity..."
    if ! ping -c 3 github.com >/dev/null 2>&1; then
      echo "Error: No network connectivity."
      exit 1
    fi

    echo "Detecting storage devices..."
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT || { echo "Failed to detect storage devices"; exit 1; }

    echo "Please enter the target device for installation (e.g., /dev/sda, /dev/mmcblk0, /dev/nvme0n1):"
    read TARGET_DEVICE

    if [ ! -b "\$TARGET_DEVICE" ]; then
      echo "Error: \$TARGET_DEVICE is not a valid block device."
      exit 1
    fi

    echo "Do you want to install the boot partition on the EMMC (/dev/mmcblk0)? (y/N)"
    read USE_EMMC
    if [ "\$USE_EMMC" = "y" ] || [ "\$USE_EMMC" = "Y" ]; then
      BOOT_DEVICE="/dev/mmcblk0"
      echo "Will use EMMC (\$BOOT_DEVICE) for boot partition"
    else
      BOOT_DEVICE="\$TARGET_DEVICE"
      echo "Will use \$BOOT_DEVICE for boot partition"
    fi

    echo "WARNING: This will erase all data on \$TARGET_DEVICE. Are you sure? (y/N)"
    read CONFIRM
    if [ "\$CONFIRM" != "y" ] && [ "\$CONFIRM" != "Y" ]; then
      echo "Aborted by user."
      exit 1
    fi

    echo "Clearing existing partition tables..."
    sgdisk --zap-all "\$TARGET_DEVICE" || { echo "Failed to clear partition tables"; exit 1; }
    partprobe "\$TARGET_DEVICE"
    udevadm settle
    sleep 3

    echo "Verifying device readiness..."
    while ! sgdisk -p "\$TARGET_DEVICE" >/dev/null 2>&1; do
      echo "Device not ready, waiting..."
      sleep 1
    done

    echo "Creating GPT partition table..."
    sgdisk --new=1:8196:+512M --typecode=1:ef00 --change-name=1:"EFI" "\$BOOT_DEVICE" || { echo "Failed to create EFI partition"; exit 1; }
    sleep 1

    if [ "\$BOOT_DEVICE" = "\$TARGET_DEVICE" ]; then
      sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Root" "\$TARGET_DEVICE" || { echo "Failed to create root partition"; exit 1; }
      PART2="\''${TARGET_DEVICE}p2"
    else
      sgdisk --new=1:0:0 --typecode=1:8300 --change-name=1:"Root" "\$TARGET_DEVICE" || { echo "Failed to create root partition"; exit 1; }
      PART2="\''${TARGET_DEVICE}p1"
    fi
    sleep 1

    partprobe "\$TARGET_DEVICE"
    udevadm settle

    if [[ "\$BOOT_DEVICE" =~ [0-9]$ ]]; then
      PART1="\''${BOOT_DEVICE}p1"
    else
      PART1="\''${BOOT_DEVICE}1"
    fi

    if [ ! -b "\$PART1" ] || [ ! -b "\$PART2" ]; then
      echo "Error: Partitions not found."
      exit 1
    fi

    echo "Formatting EFI partition..."
    mkfs.vfat -n "EFI" "\$PART1" || { echo "Failed to format EFI partition"; exit 1; }

    echo "Formatting root partition..."
    mkfs.ext4 -L "ROOT" "\$PART2" || { echo "Failed to format root partition"; exit 1; }

    echo "Mounting partitions..."
    mount "\$PART2" /mnt || { echo "Failed to mount root partition"; exit 1; }
    mkdir -p /mnt/boot/efi || { echo "Failed to create EFI mount point"; exit 1; }
    mount "\$PART1" /mnt/boot/efi || { echo "Failed to mount EFI partition"; exit 1; }

    mkdir -p /mnt/home/\$ADMIN_USER || { echo "Failed to create home directory"; exit 1; }
    chown 1000:1000 /mnt/home/\$ADMIN_USER || { echo "Failed to set home directory ownership"; exit 1; }

    echo "Setting up SOPS key..."
    mkdir -p /mnt/var/lib/sops-nix
    cp /var/lib/sops-nix/key.txt /mnt/var/lib/sops-nix/key.txt
    chmod 600 /mnt/var/lib/sops-nix/key.txt

    echo "Installing NixOS from \$FLAKE_REF#\$HOST_NAME..."
    nixos-install --root /mnt --flake "\$FLAKE_REF#\$HOST_NAME" --no-channel-copy || { echo "Failed to install NixOS"; exit 1; }

    echo "Verifying installation..."
    if [ ! -f /mnt/etc/ssh/sshd_config ]; then
      echo "Error: SSH configuration not found."
      exit 1
    fi

    echo "Unmounting..."
    umount /mnt/boot/efi || { umount -l /mnt/boot/efi; echo "Forced unmount of EFI partition"; }
    umount /mnt || { umount -l /mnt; echo "Forced unmount of root partition"; }

    echo ""
    echo "Installation complete! Remove installation media and reboot."
    EOF
        chmod +x $out/bin/nixinstall
  '';

  meta = with lib; {
    description = "NixOS installer script";
    platforms = platforms.linux;
  };
}
