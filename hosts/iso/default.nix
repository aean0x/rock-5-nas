# Installer configuration — shared by ISO and netboot images
# Minimal bootable environment with SSH access for remote install via `./deploy install`.
{
  pkgs,
  lib,
  settings,
  ...
}:
{
  boot.supportedFilesystems = lib.mkForce [
    "ext4"
    "vfat"
  ];

  # Disable git and documentation to reduce ISO size
  programs.git.enable = false;
  documentation.enable = false;
  documentation.man.enable = false;
  documentation.doc.enable = false;

  # Networking — DHCP for flexibility, but advertise our real hostname via mDNS
  networking.hostName = settings.hostName;
  networking.useDHCP = lib.mkForce true;

  # SSH with pubkey auth (keys baked in from settings.nix)
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true; # Fallback for ISO
  };

  # mDNS for hostname.local resolution
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish.enable = true;
    publish.addresses = true;
  };

  # Admin user with SSH keys + fallback password
  users.users.${settings.adminUser} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = settings.setupPassword;
    openssh.authorizedKeys.keys = settings.sshPubKeys;
  };

  security.sudo.wheelNeedsPassword = false;

  # Useful for remote install
  environment.systemPackages = with pkgs; [
    parted
    gptfdisk
    util-linux
    rsync
  ];

  system.stateVersion = settings.stateVersion;
}
