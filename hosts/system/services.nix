# Service module imports
# Enable/disable services by uncommenting their import lines.
# Service-specific configuration (ports, containers, etc.) lives in each module.
{
  imports = [
    # ./services/cockpit.nix      # Web-based system management (port 9090)
    # ./services/caddy.nix        # Reverse proxy with automatic HTTPS
    # ./services/containers.nix   # Docker containers (HA, Matter, Tailscale, OTBR)
    ./services/remote-desktop.nix # XFCE + xrdp
    # ./services/arr-suite.nix    # Media stack (Sonarr, Radarr, Jellyfin, etc.)
    # ./services/transmission.nix # Torrent client with VPN killswitch
    ./services/tasks.nix # Auto-upgrade and garbage collection
  ];
}
