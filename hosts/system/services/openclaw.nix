# OpenClaw (native, non-Docker)
{
  config,
  pkgs,
  inputs,
  settings,
  ...
}:
let
  gatewayPort = 18789;

  steipetePkgs =
    inputs.nix-openclaw.inputs.nix-steipete-tools.packages.${pkgs.stdenv.hostPlatform.system} or { };

  toolSets = import (inputs.nix-openclaw + "/nix/tools/extended.nix") {
    inherit pkgs steipetePkgs;
  };

  # User home dir; OpenClaw naturally uses ~/.openclaw/ for state
  openclawHome = "/home/openclaw";
  openclawDataDir = "${openclawHome}/.openclaw";

  # Symlink for discoverability
  symlinkPath = "/var/lib/openclaw";

  # ===========================================================================
  # OpenClaw configuration — derived from the Docker module, adjusted for native.
  # Secrets (tokens, passwords, API keys) are injected via env vars from SOPS.
  # https://docs.openclaw.ai/gateway/configuration
  # ===========================================================================
  openclawConfig = {
    # -- Gateway ---------------------------------------------------------------
    gateway = {
      port = gatewayPort;
      mode = "local";
      bind = "auto";
      auth = {
        mode = "password"; # reads OPENCLAW_GATEWAY_PASSWORD env
        allowTailscale = true;
      };
      controlUi = {
        enabled = true;
        dangerouslyDisableDeviceAuth = true; # skip device pairing on LAN/tailscale
      };
      trustedProxies = [
        "127.0.0.1"
        "::1"
      ];
      tailscale = {
        mode = "off"; # Tailscale runs natively on host
      };
    };

    # -- Browser ---------------------------------------------------------------
    browser = {
      enabled = true;
      executablePath = "${pkgs.chromium}/bin/chromium";
      headless = true;
      noSandbox = true;
      defaultProfile = "remote";
      profiles = {
        remote = {
          cdpUrl = "__BROWSERLESS_CDP_URL__";
          color = "#00AA00";
        };
        local = {
          cdpPort = 18800;
          color = "#FF0000";
        };
      };
    };

    # -- Agent defaults --------------------------------------------------------
    agents = {
      defaults = {
        model = {
          primary = "google/gemini-flash-latest";
          fallbacks = [
            "google/gemini-2.5-flash"
            "gemini-flash"
            # "grok-medium"
          ];
        };
        models = {
          "openrouter/arcee-ai/trinity-mini:free" = {
            alias = "trinity";
          };
          "openrouter/anthropic/claude-opus-4.6" = {
            alias = "opus";
          };
          "openrouter/anthropic/claude-sonnet-4.5" = {
            alias = "sonnet";
          };
          "openrouter/anthropic/claude-haiku-4.5" = {
            alias = "haiku";
          };
          "openrouter/google/gemini-3-pro-preview" = {
            alias = "gemini-pro";
          };
          "openrouter/google/gemini-3-flash-preview" = {
            alias = "gemini-flash";
          };
          # "openrouter/x-ai/grok-4.1-fast" = {
          #   alias = "grok";
          #   params = {
          #     reasoning = {
          #       enabled = true;
          #       effort = "low";
          #     };
          #   };
          # };
          # "openrouter/x-ai/grok-4.1-fast:medium" = {
          #   alias = "grok-medium";
          #   params = {
          #     reasoning = {
          #       effort = "medium";
          #       enabled = true;
          #     };
          #   };
          # };
          # "openrouter/x-ai/grok-4.1-fast:xhigh" = {
          #   alias = "grok-xhigh";
          #   params = {
          #     reasoning = {
          #       effort = "xhigh";
          #       enabled = true;
          #     };
          #   };
          # };
        };

        memorySearch = {
          sources = [
            "memory"
            "sessions"
          ];
          experimental = {
            sessionMemory = true;
          };
          provider = "gemini";
          model = "gemini-embedding-001";
        };

        contextPruning = {
          mode = "cache-ttl";
          ttl = "6h";
          keepLastAssistants = 8;
        };

        compaction = {
          mode = "default";
          memoryFlush = {
            enabled = true;
            softThresholdTokens = 60000;
            prompt = "Extract key decisions, state changes, lessons, blockers to memory/YYYY-MM-DD.md. Format: ## [HH:MM] Topic. Skip routine work. NO_FLUSH if nothing important.";
            systemPrompt = "Compacting session context. Extract only what's worth remembering. No fluff.";
          };
        };

        heartbeat = {
          # model = "openrouter/x-ai/grok-4.1-fast";
        };

        maxConcurrent = 4;
        subagents = {
          maxConcurrent = 8;
          model = {
            # primary = "openrouter/x-ai/grok-4.1-fast";
            fallbacks = [
              # "grok-medium"
              # "grok-xhigh"
            ];
          };
        };
      };
      list = [
        {
          id = "main";
          subagents = {
            allowAgents = [ "*" ];
            model = {
              # primary = "openrouter/x-ai/grok-4.1-fast";
            };
          };
        }
      ];
    };

    # -- Plugins ---------------------------------------------------------------
    plugins = {
      entries = {
        telegram = {
          enabled = true;
        };
      };
    };

    # -- Auth profiles ---------------------------------------------------------
    auth = {
      profiles = {
        "openrouter:default" = {
          provider = "openrouter";
          mode = "api_key";
        };
        "anthropic:default" = {
          provider = "anthropic";
          mode = "api_key";
        };
        "google:default" = {
          provider = "google";
          mode = "api_key";
        };
      };
    };

    # -- Tools -----------------------------------------------------------------
    tools = {
      web = {
        search = {
          enabled = true;
        };
        fetch = {
          enabled = true;
        };
      };
      exec = {
        pathPrepend = [
          "/run/current-system/sw/bin"
          "/home/openclaw/.nix-profile/bin"
        ];
      };
    };

    # -- Channels --------------------------------------------------------------
    channels = {
      telegram = {
        enabled = true;
        dmPolicy = "pairing";
        groupPolicy = "allowlist";
        streamMode = "partial";
      };
    };

    # -- Messages --------------------------------------------------------------
    messages = {
      ackReactionScope = "group-mentions";
      tts = {
        auto = "inbound";
        provider = "edge";
        edge = {
          enabled = true;
          voice = "en-GB-RyanNeural";
        };
      };
    };

    # -- Logging ---------------------------------------------------------------
    logging = {
      redactSensitive = "tools";
    };

    # -- Commands --------------------------------------------------------------
    commands = {
      native = "auto";
      nativeSkills = "auto";
      restart = true;
    };
  };

  configFile = pkgs.writeText "openclaw-desired.json" (builtins.toJSON openclawConfig);

  # Wrapper runs CLI as the openclaw user — keeps perms tight.
  openclawCli = pkgs.writeShellScriptBin "oc" ''
    exec sudo -u openclaw \
      XDG_RUNTIME_DIR=/run/user/1540 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1540/bus \
      ${pkgs.openclaw-gateway}/bin/openclaw "$@"
  '';

  openclawPackages = [
    pkgs.openclaw-gateway
    openclawCli
    pkgs.chromium
  ]
  ++ toolSets.tools;
in
{
  services.caddy.proxyServices = {
    "openclaw.${settings.domain}" = gatewayPort;
  };

  # ==================
  # Service user/group
  # ==================
  users.users.openclaw = {
    isSystemUser = true;
    uid = 1000;
    group = "openclaw";
    description = "OpenClaw service user";
    home = openclawHome;
    createHome = true;
    shell = pkgs.bash;
  };

  users.groups.openclaw = {
    gid = 1000;
  };

  # ===================
  # Packages (system-wide, available to all users including admin SSH)
  # ===================
  environment.systemPackages = openclawPackages;

  # ===================
  # Symlink for discoverability
  # ===================
  systemd.tmpfiles.rules = [
    "d ${openclawDataDir} 0700 openclaw openclaw -"
    "d /tmp/openclaw 0700 openclaw openclaw -"
    "L+ ${symlinkPath} - - - - ${openclawDataDir}"
  ];

  # ===================
  # Secrets injector (root one-shot, lifecycle tied to gateway)
  # ===================
  systemd.services.openclaw-secrets = {
    description = "OpenClaw secrets injector";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      # Write Google Workspace MCP credentials from SOPS
      GWS_DIR="${openclawDataDir}/credentials"
      mkdir -p "$GWS_DIR"
      GWS_ID="$(cat ${config.sops.secrets.google_workspace_client_id.path})"
      GWS_SECRET="$(cat ${config.sops.secrets.google_workspace_client_secret.path})"
      printf '{"installed":{"client_id":"%s","project_id":"clawdbot-486907","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_secret":"%s","redirect_uris":["http://localhost"]}}\n' \
        "$GWS_ID" "$GWS_SECRET" > "$GWS_DIR/google_credentials.json"
      chown openclaw:openclaw "$GWS_DIR" "$GWS_DIR/google_credentials.json"
      chmod 0700 "$GWS_DIR"
      chmod 0600 "$GWS_DIR/google_credentials.json"

      # Write API keys to environment file
      printf '%s\n' \
        "OPENCLAW_GATEWAY_TOKEN=$(cat ${config.sops.secrets.openclaw_gateway_token.path})" \
        "OPENCLAW_GATEWAY_PASSWORD=$(cat ${config.sops.secrets.openclaw_gateway_password.path})" \
        "OPENROUTER_API_KEY=$(cat ${config.sops.secrets.openrouter_api_key.path})" \
        "OPENAI_API_KEY=$(cat ${config.sops.secrets.openrouter_api_key.path})" \
        "ANTHROPIC_API_KEY=$(cat ${config.sops.secrets.anthropic_api_key.path})" \
        "BRAVE_API_KEY=$(cat ${config.sops.secrets.brave_search_api_key.path})" \
        "TELEGRAM_BOT_TOKEN=$(cat ${config.sops.secrets.telegram_bot_token.path})" \
        "GOOGLE_PLACES_API_KEY=$(cat ${config.sops.secrets.google_places_api_key.path})" \
        "GOOGLE_DRIVE_OAUTH_CREDENTIALS=${openclawDataDir}/credentials/google_credentials.json" \
        "GOOGLE_DRIVE_TOKENS=${openclawDataDir}/credentials/google_tokens.json" \
        "BROWSERLESS_API_TOKEN=$(cat ${config.sops.secrets.browserless_api_token.path})" \
        "MATON_API_KEY=$(cat ${config.sops.secrets.maton_api_key.path})" \
        "HA_TOKEN=$(cat ${config.sops.secrets.ha_token.path})" \
        "HA_URL=$(cat ${config.sops.secrets.ha_url.path})" \
        "GOOGLE_API_KEY=$(cat ${config.sops.secrets.google_api_key.path})" \
        "GEMINI_API_KEY=$(cat ${config.sops.secrets.google_api_key.path})" \
        "XAI_API_KEY=$(cat ${config.sops.secrets.xai_api_key.path})" \
        > /run/openclaw.env
      chmod 0640 /run/openclaw.env
      chown root:openclaw /run/openclaw.env
    '';
  };

  # ===================
  # OpenClaw user service
  # ===================
  systemd.user.services.openclaw-gateway = {
    description = "OpenClaw gateway";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];
    path = openclawPackages ++ [ "/run/current-system/sw" ];
    environment = {
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = openclawHome;
      EnvironmentFile = "/run/openclaw.env";
      UMask = "0077";
      ExecStartPre =
        let
          configPath = "${openclawDataDir}/openclaw.json";
        in
        pkgs.writeShellScript "openclaw-config-merge" ''
          set -euo pipefail

          # Wait for secrets injector (system service) to create env file
          for attempt in $(seq 1 30); do
            [ -f /run/openclaw.env ] && break
            echo "Waiting for /run/openclaw.env ($attempt/30)..."
            sleep 2
          done
          [ -f /run/openclaw.env ] || { echo "ERROR: /run/openclaw.env not found after 60s"; exit 1; }

          # Tighten any dirs/files the gateway may have created with lax permissions
          find "${openclawDataDir}" -type d -not -perm 0700 -exec chmod 0700 {} +
          find "${openclawDataDir}" -type f -not -perm 0600 -exec chmod 0600 {} +

          CONF="${configPath}"
          if [ -f "$CONF" ]; then
            ${pkgs.jq}/bin/jq -s '
              def merge:
                if length == 2 and (.[0] | type) == "object" and (.[1] | type) == "object"
                then .[0] as $a | .[1] as $b |
                  ($a | keys) + ($b | keys) | unique | map(. as $k |
                    if ($a | has($k)) and ($b | has($k))
                    then { ($k): ([$a[$k], $b[$k]] | merge) }
                    elif ($b | has($k)) then { ($k): $b[$k] }
                    else { ($k): $a[$k] }
                    end
                  ) | add // {}
                else .[-1]
                end;
              merge
            ' "$CONF" ${configFile} > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
          else
            cp ${configFile} "$CONF"
          fi

          # Inject gateway password and token so CLI can authenticate with the gateway
          if [ -n "''${OPENCLAW_GATEWAY_PASSWORD:-}" ] && [ -n "''${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
            ${pkgs.jq}/bin/jq \
              --arg pass "$OPENCLAW_GATEWAY_PASSWORD" \
              --arg token "$OPENCLAW_GATEWAY_TOKEN" \
              '.gateway.auth.password = $pass | .gateway.auth.token = $token | .gateway.remote.password = $pass | .gateway.remote.token = $token' \
              "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
          fi

          # Inject browserless CDP URL with runtime API token
          if [ -n "''${BROWSERLESS_API_TOKEN:-}" ]; then
            ${pkgs.jq}/bin/jq \
              --arg url "https://production-ams.browserless.io/?token=''${BROWSERLESS_API_TOKEN}&stealth=true?blockAds=true" \
              '.browser.profiles.remote.cdpUrl = $url' \
              "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
          fi

          chmod 0600 "$CONF"
        '';
      ExecStart = "${pkgs.openclaw-gateway}/bin/openclaw gateway --port ${toString gatewayPort}";
      Restart = "always";
      RestartSec = "2s";
    };
  };

  # Enable lingering so user service starts at boot without login
  users.users.openclaw.linger = true;

}
