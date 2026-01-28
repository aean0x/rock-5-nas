# Storage configuration for ROCK5 ITX
{
  pkgs,
  ...
}:

{
  # ZFS configuration
  boot = {
    supportedFilesystems = [ "zfs" ];
    zfs.forceImportRoot = false;
  };

  services.zfs = {
    autoScrub.enable = true;
    autoSnapshot = {
      enable = true;
      frequent = 4;
      hourly = 24;
      daily = 7;
      weekly = 4;
      monthly = 12;
    };
    trim.enable = true;
  };

  environment.systemPackages = with pkgs; [
    zfs
    zfs-prune-snapshots
  ];
}
