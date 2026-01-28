# System management scripts
{ pkgs, settings, ... }:

let
  flakeRef = "github:${settings.repoOwner}/${settings.repoName}#${settings.hostName}";
in
{
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "rebuild" ''
      set -euo pipefail
      echo "Rebuilding from ${flakeRef}..."
      sudo nixos-rebuild switch --flake "${flakeRef}" "$@"
      echo "Rebuild complete."
    '')

    (writeShellScriptBin "rebuild-boot" ''
      set -euo pipefail
      echo "Rebuilding (boot) from ${flakeRef}..."
      sudo nixos-rebuild boot --flake "${flakeRef}" "$@"
      echo "Rebuild complete. Reboot to apply changes."
    '')

    (writeShellScriptBin "cleanup" ''
      set -euo pipefail
      echo "Collecting garbage..."
      sudo nix-collect-garbage -d | grep freed || true
      echo "Optimizing store..."
      sudo nix-store --optimise
      echo "Cleanup complete."
    '')

    (writeShellScriptBin "system-info" ''
      echo "=== NixOS System Info ==="
      echo "Hostname: $(hostname)"
      echo "Flake: ${flakeRef}"
      echo ""
      echo "=== Current Generation ==="
      sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -5
      echo ""
      echo "=== Disk Usage ==="
      df -h / /nix 2>/dev/null || df -h /
      echo ""
      echo "=== Store Size ==="
      du -sh /nix/store 2>/dev/null || echo "Unable to calculate"
    '')
  ];
}
