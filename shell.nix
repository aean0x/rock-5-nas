# Development shell for NixOS configuration management
# Usage: nix-shell
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Secrets management (encrypt/decrypt)
    age
    sops

    # Remote deployment
    openssh

    # Build tools
    nix
    git

    # Used in scripts
    gnugrep
    gnused
    coreutils
    bash
  ];

  shellHook = ''
    echo "NAS development shell"
    echo ""
    echo "Available commands:"
    echo "  ./build-iso          - Build installer ISO"
    echo "  ./deploy <cmd>       - Remote NAS management"
    echo "  ./secrets/encrypt    - Encrypt secrets"
    echo "  ./secrets/decrypt    - Decrypt secrets for editing"
    echo ""
  '';
}
