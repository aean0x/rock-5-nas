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
   ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
   cat ~/.ssh/id_ed25519.pub
   ```

3. **Configure Settings**
   
   Edit `settings.nix` with your specific configuration:
   - Update `hostName` if desired
   - Set your `adminUser` username
   - Add your SSH public key to the `sshKeys` list
   - Review and adjust other settings as needed

4. **Configure Secrets**
   
   Set up secrets with [Managing Secrets](#managing-secrets)

5. **Commit Your Changes**
   ```bash
   git commit -m "Initial configuration"
   git push
   ```
   This ensures your configuration is available during installation.

## Bootloader Configuration

Before building the ISO, you need to flash the EDK2 UEFI firmware to your ROCK5 ITX board. This is required for proper booting and installation.

1. **Download Required Files**
   - [rk3588_spl_loader_v1.15.113.bin](https://dl.radxa.com/rock5/sw/images/loader/rk3588_spl_loader_v1.15.113.bin) - SPI bootloader image
   - [rock-5itx_UEFI_Release_v0.11.2.img](https://github.com/edk2-porting/edk2-rk3588/releases/) - UEFI bootloader image for "rock-5-itx"

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
   - Ensures SOPS encryption is set up
   - Builds the ISO with the encryption key included (required to build the final system)
   - Outputs the ISO to `result/iso/`

2. **Write the ISO to a USB Drive**
   ```bash
   # Replace /dev/sdX with your USB drive
   sudo dd if=result/iso/nixos-minimal-xxxxxxxxxx.iso of=/dev/sdX bs=4M status=progress
   ```

## Installation

1. **Boot from the ISO**
   - Insert the USB drive into your ROCK5 ITX
   - Boot from the USB drive

2. **Run the Installer**
   ```bash
   sudo nixinstall
   ```
   The installer will:
   - Partition and format the target drive
   - Install NixOS with your configuration
   - Set up SSH access
   - Configure your user account

3. **First Boot**
   - Remove the installation media
   - Reboot the system
   - SSH into your new system using your configured key:
     ```bash
     ssh your_username@your_hostname
     ```

## System Management

The system is configured to use your repository in `~/.dotfiles` for configuration management.

### Available Management Scripts

1. **Rebuild System** (`~/.local/bin/rebuild`)
   ```bash
   rebuild        # Rebuild without reboot
   rebuild -r     # Rebuild and reboot
   rebuild -u     # Update and rebuild
   ```

2. **Cleanup Nix Store** (`~/.local/bin/cleanup`)
   ```bash
   cleanup        # Remove old generations and verify store
   ```

### Managing Secrets

1. **Initial Secrets Setup**
   ```bash
   cd ~/.dotfiles/secrets
   ./encrypt.sh
   ```
   This will:
   - Generate an age encryption key
   - Create a working copy of secrets from the example
   - Encrypt your secrets

2. **View/Edit Secrets**
   ```bash
   cd ~/.dotfiles/secrets
   ./decrypt.sh   # Creates secrets.yaml.work
   # Edit secrets.yaml.work with your values:
   # - Set your user's hashed password
   # - Configure any other required secrets
   ./encrypt.sh   # Encrypts changes
   ```

3. **Apply Changes**
   ```bash
   rebuild        # Rebuild system with new secrets
   ```


