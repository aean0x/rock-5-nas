# SOPS secrets configuration
# Decrypted at runtime via sops-nix
{
  config,
  lib,
  settings,
  ...
}:
let
  wifiEnabled = settings.enableWifi or false;
in
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";

    secrets = lib.mkMerge [
      {
        user_hashedPassword = { };
        tailscale_authKey = { };
      }
      (lib.mkIf wifiEnabled {
        wifi_psk = { };
      })
    ];

    templates = lib.mkIf wifiEnabled {
      wifiEnv = {
        owner = "root";
        group = "root";
        mode = "0400";
        path = "/run/wifi.env";
        content = ''
          WIFI_PSK="${config.sops.placeholder."wifi_psk"}"
        '';
      };
    };
  };
}
