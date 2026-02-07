#!/usr/bin/env bash
# Build ISO image and optionally write to USB
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "${REPO_ROOT}"

check_aarch64_support

info "Building ISO image for ${HOST}..."
nix build .#iso --print-build-logs --show-trace

echo ""
info "ISO built successfully!"
echo "Output: result/iso/*.iso"
echo ""
read -p "Do you want to write this ISO to a USB drive now? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    lsblk
    echo ""
    read -p "Enter target device path (e.g. /dev/sdX): " DEVICE

    if [[ -z "$DEVICE" ]]; then
        error "No device specified."
        exit 1
    fi

    if [[ ! -e "$DEVICE" ]]; then
        error "Device $DEVICE not found."
        exit 1
    fi

    warn "WARNING: ALL DATA ON $DEVICE WILL BE ERASED!"
    read -p "Are you absolutely sure? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Writing to $DEVICE..."
        sudo dd if="$(ls result/iso/*.iso)" of="$DEVICE" bs=4M status=progress
        sync
        info "Done! You can remove the USB drive."
    else
        echo "Aborted."
    fi
else
    echo "Write to USB manually with:"
    echo "  sudo dd if=\"\$(ls result/iso/*.iso)\" of=/dev/sdX bs=4M status=progress && sync"
fi

echo ""
echo "After booting the device from the ISO, run:"
echo "  ./deploy install"
