# System tasks and cron jobs
{ settings, ... }:

let
  flakeRef = "github:${settings.repoUrl}#${settings.hostName}";
in
{
  # Automatic system upgrades
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    flake = flakeRef;
    dates = "Sun *-*-* 03:00:00";
    randomizedDelaySec = "30min";
  };

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Weekly gateway restart (clears stale sessions, re-syncs channels)
  systemd.timers.openclaw-gateway-restart = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed *-*-* 04:17:00";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };
  systemd.services.openclaw-gateway-restart = {
    description = "Restart OpenClaw gateway";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/docker restart openclaw-gateway";
    };
  };
}
