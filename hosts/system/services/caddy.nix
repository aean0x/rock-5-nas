{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.caddy;

  # Generates a pair of vhosts (HTTP redirect + HTTPS proxy) for a given domain/port
  mkProxy = host: port: {
    "http://${host}" = {
      extraConfig = "redir https://${host}{uri}";
    };
    "https://${host}" = {
      extraConfig = ''
        tls internal
        reverse_proxy 127.0.0.1:${toString port} {
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
        }
      '';
    };
  };

  # Flatten the proxyServices map into a single attribute set of Caddy virtualHosts
  generatedVHosts = lib.foldl' (acc: host: acc // (mkProxy host cfg.proxyServices.${host})) { } (
    builtins.attrNames cfg.proxyServices
  );

in
{
  options.services.caddy = {
    proxyServices = lib.mkOption {
      description = "Map of hostnames (or IPs) to backend ports. Automatically configures internal TLS and HTTP redirects.";
      type = lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.int
          lib.types.str
        ]
      );
      default = { };
    };
  };

  config = {
    services.caddy = {
      enable = true;
      package = pkgs.caddy;

      # Default bindings go to Home Assistant
      proxyServices."192.168.1.200" = 8123;
      proxyServices."rocknas.local" = 8123;

      virtualHosts = generatedVHosts;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
