{
  pkgs,
  lib,
  config,
  settings,
  ...
}:
let
  # Workaround to pass the key.txt file to the ISO. Ensure the KEY_FILE_PATH environment
  # variable is set to the path of the key.txt file before running nix-build
  keyFilePath = builtins.getEnv "KEY_FILE_PATH";
  keyContent = if keyFilePath != "" then builtins.readFile keyFilePath else "";
in
{
  imports = [
    ../common/kernel.nix
  ];

  system.stateVersion = "25.11";

  boot.supportedFilesystems = lib.mkForce [
    "ext4"
    "vfat"
  ];

  # ISO specific configuration
  isoImage = {
    isoName = "${settings.hostName}-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.iso";
    volumeID = "${settings.hostName}_${config.system.nixos.label}";
    makeEfiBootable = true;
    makeBiosBootable = false;
  };

  # Disable git and documentation to avoid build issues during ISO cross-compilation
  programs.git.enable = false;
  documentation.enable = false;
  documentation.man.enable = false;
  documentation.doc.enable = false;

  # Include install script
  environment.systemPackages = with pkgs; [
    (callPackage ./install.nix { inherit settings; })
  ];

  # Ensure networking is enabled
  networking.useDHCP = lib.mkForce true;

  # Enable SSH for remote setup
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  # Default user for ISO
  users.users.setup = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "nixos";
  };

  # Activation script to include key.txt
  system.activationScripts = {
    setupSopsKey =
      if keyContent != "" then
        ''
          mkdir -p /var/lib/sops-nix
          echo "${keyContent}" > /var/lib/sops-nix/key.txt
          chmod 600 /var/lib/sops-nix/key.txt
        ''
      else
        ''
          echo "Error: KEY_FILE_PATH environment variable not set or file not found."
          exit 1
        '';
  };
}
