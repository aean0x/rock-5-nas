#!/usr/bin/env bash
# Build netboot images
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "${REPO_ROOT}"

check_aarch64_support

info "Building netboot images for ${HOST}..."
nix build .#netboot --print-build-logs --show-trace

echo ""
info "Netboot built successfully!"
echo "Output: result/"
ls -lh result/
echo ""
echo "To start the PXE server:"
echo "  ./deploy netboot"
