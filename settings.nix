{
  # System
  hostName = "rock5-nas";
  adminUser = "aean";
  setupPassword = "nixos"; # For SSH into the setup image
  description = "ROCK5 ITX NAS Server";
  hostId = "8425e349"; # Required for ZFS, generated with `head -c 8 /etc/machine-id`

  # Build systems
  hostSystem = "x86_64-linux"; # System building the ISO
  targetSystem = "aarch64-linux"; # System that will run the OS

  # URLs
  edk2FirmwareUrl = "https://github.com/edk2-porting/edk2-rk3588/releases/download/v1.1/rock-5-itx_UEFI_Release_v1.1.img";
  spiFirmwareUrl = "https://dl.radxa.com/rock5/sw/images/loader/rk3588_spl_loader_v1.15.113.bin";
  repoUrl = "https://github.com/aean0x/rock-5-nas.git";

  # Replace with your SSH public key(s)
  # Generate with: ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub && cat ~/.ssh/id_ed25519.pub
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIbxwWbFkWQb+BozyJkDXbfIdnKXoCAwJkTQMncdyG5r aean@nix-pc"
  ];

  # SOPS configuration
  # TODO: Add secrets to match the secrets.yaml.example file
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets = {
      "user.hashedPassword" = { };
      "services.nextcloud.adminpass" = { };
    };
  };
}
