# Rock 5 NAS

A NixOS configuration for the ROCK5 ITX board, featuring automated installation and secure secrets management.

Intended to provide a straightforward, all-in-one guide and repo for installing and managing a headless NixOS server setup on a Rock 5 ITX board.

## Prerequisites

- A Linux system with Nix installed
- Git
- SSH key pair (for secure management)

## Initial Setup

1. **Fork and Clone the Repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/rock-5-nas.git
   cd rock-5-nas
   ```

2. **Generate SSH Key** (if you don't have one)
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   cat ~/.ssh/id_ed25519.pub
   ```

3. **Configure Settings**
   
   Edit `settings.nix` with your specific configuration:
   - Update `repoUrl` to match your fork (e.g., `"your-username/rock-5-nas"`)
   - Update `hostName` if desired
   - Set your `adminUser` username

4. **Configure Secrets**
   
   Run the encryption script to set up your secrets:
   ```bash
   cd secrets
   ./encrypt.sh
   ```
   This will:
   - Generate an age encryption key (if none exists)
   - Create `.sops.yaml` with your public key
   - Open `secrets.yaml.work` in nano for editing
   - Encrypt your secrets when you save and exit

   Fill in the required values (see `secrets.yaml.example` for full schema):
   - `user.hashedPassword` - Generate with `mkpasswd -m SHA-512`
   - `user.pubKey` - Your SSH public key from step 2

5. **Commit Your Changes**
   ```bash
   git add .
   git commit -m "Initial configuration"
   git push
   ```
   This ensures your configuration is available during installation.

## Bootloader Configuration

Before building the ISO, you need to flash the EDK2 UEFI firmware to your ROCK5 ITX board. This is required for proper booting and installation.

1. **Download Required Files**
   - [rk3588_spl_loader_v1.15.113.bin](https://dl.radxa.com/rock5/sw/images/loader/rk3588_spl_loader_v1.15.113.bin) - SPI bootloader image
   - [rock-5-itx_UEFI_Release_v1.1.img](https://github.com/edk2-porting/edk2-rk3588/releases/) - UEFI bootloader image for "rock-5-itx"

2. **Flash the Bootloader**
   ```bash
   # Install rkdeveloptool
   nix-shell -p rkdeveloptool

   # Download bootloader
   sudo rkdeveloptool db rk3588_spl_loader_v1.15.113.bin

   # Write UEFI image
   sudo rkdeveloptool wl 0 rock-5-itx_UEFI_Release_vX.XX.X.img

   # Reset device
   sudo rkdeveloptool rd
   ```

3. **Configure UEFI Settings**
   - Press `Escape` during boot to enter UEFI settings
   - Navigate to `ACPI / Device Tree`
   - Enable `Support DTB override & overlays`

## Building the ISO

1. **Build the ISO with SOPS Integration**
   ```bash
   ./build-iso.sh
   ```
   This script:
   - Validates that `settings.nix` matches your git remote (prompts to edit if not)
   - Ensures SOPS encryption is set up
   - Builds the ISO with the encryption key included (required to build the final system)
   - Outputs the ISO to `result/`

2. **Write the ISO to a USB Drive**
   ```bash
   # Replace /dev/sdX with your USB drive
   sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress
   ```

## Installation

1. **Boot from the ISO**
   - Insert the USB drive into your ROCK5 ITX
   - Boot from the USB drive

2. **Connect via SSH** (optional)
   ```bash
   ssh setup@<device-ip>
   # Password: nixos (or as set in settings.setupPassword)
   ```

3. **Run the Installer**
   ```bash
   sudo nixinstall
   ```
   The installer will:
   - List available storage devices
   - Partition and format the target drive (with optional EMMC boot)
   - Copy the SOPS key for secret decryption
   - Install NixOS from your remote flake
   - Set up SSH access and your user account

4. **First Boot**
   - Remove the installation media
   - Reboot the system
   - SSH into your new system using your configured key:
     ```bash
     ssh your_username@your_hostname
     ```

## System Management

The system fetches configuration directly from your GitHub repository. To make changes, edit files locally, commit, push, then run `rebuild` on the NAS.

### Available Commands

| Command | Description |
|---------|-------------|
| `rebuild` | Rebuild system from remote flake |
| `rebuild-boot` | Rebuild and apply on next reboot |
| `cleanup` | Garbage collect and optimize nix store |
| `system-info` | Show system status and disk usage |

Pass additional flags to `rebuild` as needed (e.g., `rebuild --upgrade`).

### Editing Secrets

On the installed system or your dev machine:

```bash
cd /path/to/rock-5-nas/secrets
./decrypt.sh          # Decrypt to secrets.yaml.work
nano secrets.yaml.work
./encrypt.sh          # Re-encrypt changes
```

Then commit, push, and `rebuild` to apply.