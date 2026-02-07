# Docker containers: Home Assistant, Matter, OTBR, Tailscale
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  containerNames = builtins.attrNames config.virtualisation.oci-containers.containers;

  # Service ports
  haPort = 8123;
  matterPort = 5580;
  otbrPort = 8082;
  otbrRestPort = 8081;
in
{
  # ===================
  # Docker Engine
  # ===================
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };

  # ===================
  # Podman (daemonless, for ZFS-backed containers)
  # ===================
  virtualisation.podman = {
    enable = true;
    dockerCompat = false; # Keep false when real Docker daemon is enabled
    defaultNetwork.settings.dns_enabled = true;
    autoPrune.enable = true;
  };

  virtualisation.containers.storage.settings = {
    storage = {
      driver = "zfs";
      graphroot = "/var/lib/containers/storage";
    };
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      # ===================
      # Home Assistant
      # ===================
      home-assistant = {
        image = "ghcr.io/home-assistant/home-assistant:stable";
        volumes = [
          "/var/lib/home-assistant:/config"
          "/run/dbus:/run/dbus:ro"
        ];
        environment = {
          TZ = settings.timeZone;
        };
        extraOptions = [
          "--network=host"
          "--cap-add=NET_ADMIN"
          "--cap-add=NET_RAW"
        ];
        autoStart = true;
      };

      # ===================
      # Matter Server
      # ===================
      matter-server = {
        image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
        volumes = [
          "/var/lib/matter-server:/data"
          "/run/dbus:/run/dbus:ro"
        ];
        extraOptions = [
          "--network=host"
          "--cap-add=NET_ADMIN"
          "--cap-add=NET_RAW"
        ];
        cmd = [
          "--storage-path"
          "/data"
          "--primary-interface"
          "${settings.network.interface}"
        ];
        autoStart = true;
      };

      # ===================
      # Tailscale VPN
      # ===================
      tailscale = {
        image = "tailscale/tailscale:stable";
        volumes = [ "/var/lib/tailscale:/var/lib/tailscale" ];
        environmentFiles = [ "/run/tailscale.env" ];
        environment = {
          TS_STATE_DIR = "/var/lib/tailscale";
          TS_EXTRA_ARGS = "--ssh --accept-routes --accept-dns";
          TS_ROUTES = "192.168.1.0/24";
        };
        extraOptions = [
          "--network=host"
          "--cap-add=NET_ADMIN"
          "--cap-add=NET_RAW"
          "--device=/dev/net/tun"
          "--ulimit=nofile=65536:65536"
        ];
        autoStart = true;
      };

      # ===================
      # OpenThread Border Router (OTBR)
      # Uncomment when Thread radio hardware is connected
      # ===================
      otbr = {
        image = "ghcr.io/ownbee/hass-otbr-docker:latest";
        volumes = [
          "/var/lib/otbr:/data"
          "/run/dbus:/run/dbus:ro"
        ];
        environment = {
          DEVICE = "/dev/ttyACM0";
          BAUDRATE = "${toString settings.baudRate}";
          FLOW_CONTROL = "0";
          FIREWALL = "1";
          NAT64 = "1";
          OTBR_MDNS = "avahi";
          OT_INFRA_IF = settings.network.interface;
          OT_LOG_LEVEL = "info";
          OT_WEB_PORT = "${toString otbrPort}";
          OT_REST_LISTEN_ADDR = "0.0.0.0";
          OT_REST_LISTEN_PORT = "${toString otbrRestPort}";
        };
        extraOptions = [
          "--network=host"
          "--privileged"
          "--cap-add=NET_ADMIN"
          "--cap-add=NET_RAW"
          "--device=${settings.threadRadioPath}:/dev/ttyACM0"
          "--device=/dev/net/tun"
        ];
        autoStart = true;
      };

      # ===================
      # Pi-hole DNS
      # ===================
      # pihole = {
      #   image = "pihole/pihole:latest";
      #   volumes = [
      #     "/var/lib/pihole/etc-pihole:/etc/pihole"
      #     "/var/lib/pihole/etc-dnsmasq.d:/etc/dnsmasq.d"
      #   ];
      #   environment = {
      #     TZ = settings.timeZone;
      #     DNS1 = settings.network.dnsPrimary;
      #     DNS2 = settings.network.dnsSecondary;
      #   };
      #   extraOptions = [
      #     "--network=host"
      #     "--cap-add=NET_ADMIN"
      #   ];
      #   autoStart = true;
      # };
    };
  };

  # ===================
  # Kernel Sysctl
  # ===================
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv4.conf.default.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;
    "net.ipv6.conf.docker0.disable_ipv6" = 1;
    "net.ipv6.conf.all.accept_ra" = 2;
    "net.ipv6.conf.default.accept_ra" = 2;
    "net.ipv6.conf.${settings.network.interface}.accept_ra" = 2;
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
    "net.ipv6.conf.all.accept_ra_rt_info_max_plen" = 64;
  };

  # ===================
  # Firewall
  # ===================
  networking.firewall = {
    allowedTCPPorts = [
      haPort
      matterPort
      otbrPort
      otbrRestPort
    ];
    allowedUDPPorts = [
      5353 # mDNS
    ];
  };

  # ===================
  # Periodic restart timer
  # ===================
  systemd.timers.restart-services = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:30:00";
      Persistent = true;
    };
  };

  systemd.services.restart-services = {
    script = ''
      ${config.virtualisation.docker.package}/bin/docker restart \
        ${builtins.concatStringsSep " " containerNames} || true
    '';
    serviceConfig.Type = "oneshot";
  };

  # ===================
  # Auto-pull container images
  # ===================
  systemd.timers.pull-containers = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 02:00:00";
      Persistent = true;
    };
  };

  systemd.services.pull-containers = {
    script = builtins.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: container: "${config.virtualisation.docker.package}/bin/docker pull ${container.image}"
      ) config.virtualisation.oci-containers.containers
    );
    serviceConfig.Type = "oneshot";
  };

  # ===================
  # Glue Scripts
  # ===================
  systemd.services.docker-tailscale.preStart = ''
    if [ -f "${config.sops.secrets.tailscale_authKey.path}" ]; then
      echo "TS_AUTHKEY=$(cat ${config.sops.secrets.tailscale_authKey.path})" > /run/tailscale.env
    else
      echo "TS_AUTHKEY=" > /run/tailscale.env
    fi
  '';

  # Useful extras
  environment.systemPackages = with pkgs; [
    docker-compose
    podman-compose
    dive
  ];

  users.users.${settings.adminUser}.extraGroups = [
    "docker"
    "podman"
  ];
}
