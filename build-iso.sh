#!/usr/bin/env bash
set -euo pipefail

# Ensure we're in the repository root
cd "$(dirname "$0")"

# Run encrypt.sh to ensure we have a key and encrypted secrets
echo "Setting up SOPS encryption..."
cd secrets
./encrypt.sh
cd ..

# Get the key path
KEY_PATH="$(pwd)/secrets/key.txt"
if [ ! -f "$KEY_PATH" ]; then
    echo "Error: key.txt not found in secrets directory"
    exit 1
fi

# Export the key path for the ISO build
export KEY_FILE_PATH="$KEY_PATH"

# Build the ISO
echo "Building ISO with SOPS key..."
nix build .#iso --impure

echo "ISO build complete! The ISO can be found in the result directory."
