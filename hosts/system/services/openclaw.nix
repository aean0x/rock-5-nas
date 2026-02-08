# OpenClaw stack (Docker)
# Config is deep-merged into openclaw.json via preStart — declared keys always win,
# runtime state (meta, wizard, devices, sessions) survives across restarts.
# To inspect live config: ./deploy ssh "sudo cat /var/lib/openclaw/config/openclaw.json"
{
  config,
  pkgs,
  ...
}:
let
  gatewayPort = 18789;
  bridgePort = 18790;

  # ===========================================================================
  # OpenClaw configuration — edit this attrset, remote-switch to apply.
  # Secrets (tokens, passwords, API keys) are injected via env vars from SOPS.
  # ===========================================================================
  openclawConfig = {

    # -- Gateway ---------------------------------------------------------------
    gateway = {
      port = gatewayPort;
      mode = "local";
      bind = "lan";
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
        "172.17.0.1" # Docker bridge gateway
      ];
      tailscale = {
        mode = "off"; # Tailscale runs natively on host, not in container
      };
    };

    # -- Agent defaults --------------------------------------------------------
    agents = {
      defaults = {
        model = {
          primary = "openrouter/anthropic/claude-sonnet-4.5";
          fallbacks = [
            "openrouter/anthropic/claude-opus-4.6"
            "openrouter/google/gemini-3-pro-preview"
            "openrouter/google/gemini-3-flash-preview"
            "openrouter/x-ai/grok-4.1-fast"
            "openrouter/openai/gpt-4.1-mini"
            "openrouter/openai/gpt-4.1-nano"
          ];
        };
        models = {
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
          "openrouter/google/gemini-2.5-flash" = {
            alias = "gemini-2.5";
          };
          "openrouter/x-ai/grok-4.1-fast" = {
            alias = "grok";
          };
          "openrouter/openai/gpt-4.1-mini" = {
            alias = "gpt-mini";
          };
          "openrouter/openai/gpt-4.1-nano" = {
            alias = "gpt-nano";
          };
        };
        workspace = "/home/node/.openclaw/workspace";

        memorySearch = {
          sources = [
            "memory"
            "sessions"
          ];
          experimental = {
            sessionMemory = true;
          };
          provider = "openai";
          model = "text-embedding-3-small";
        };

        contextPruning = {
          mode = "cache-ttl";
          ttl = "6h";
          keepLastAssistants = 3;
        };

        compaction = {
          mode = "default";
          memoryFlush = {
            enabled = true;
            softThresholdTokens = 40000;
            prompt = "Extract key decisions, state changes, lessons, blockers to memory/YYYY-MM-DD.md. Format: ## [HH:MM] Topic. Skip routine work. NO_FLUSH if nothing important.";
            systemPrompt = "Compacting session context. Extract only what's worth remembering. No fluff.";
          };
        };

        heartbeat = {
          model = "openrouter/openai/gpt-4.1-nano";
        };

        maxConcurrent = 4;
        subagents = {
          maxConcurrent = 8;
        };
      };
      list = [
        {
          id = "main";
          default = true;
        }
      ];
    };

    # -- Auth profiles ---------------------------------------------------------
    # Tokens live in env vars (OPENROUTER_API_KEY, ANTHROPIC_API_KEY, etc.)
    # or in /home/node/.openclaw/credentials/ (volume-mounted)
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
      };
    };

    # -- Custom model providers ------------------------------------------------
    # models = {
    #   mode = "merge";
    #   providers = {
    #     synthetic = {
    #       baseUrl = "https://api.synthetic.new/anthropic";
    #       api = "anthropic-messages";
    #       models = [
    #         {
    #           id = "hf:zai-org/GLM-4.7"; name = "GLM-4.7";
    #           reasoning = false; input = [ "text" ];
    #           cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
    #           contextWindow = 198000; maxTokens = 128000;
    #         }
    #         {
    #           id = "hf:moonshotai/Kimi-K2.5"; name = "Kimi K2.5";
    #           reasoning = true; input = [ "text" ];
    #           cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
    #           contextWindow = 256000; maxTokens = 8192;
    #         }
    #       ];
    #     };
    #   };
    # };

    # -- Tools -----------------------------------------------------------------
    tools = {
      web = {
        search = {
          enabled = true;
        }; # uses BRAVE_SEARCH_API_KEY env if set
        fetch = {
          enabled = true;
        };
      };
    };

    # -- Channels --------------------------------------------------------------
    # Uncomment and configure as needed. Bot tokens come from env vars.
    channels = {
      telegram = {
        enabled = true;
        dmPolicy = "pairing";
        groupPolicy = "allowlist";
        streamMode = "partial";
        # botToken from TELEGRAM_BOT_TOKEN env
      };
      #   discord = {
      #     enabled = true;
      #     groupPolicy = "allowlist";
      #     dm = { enabled = true; policy = "allowlist"; allowFrom = [ "YOUR_USER_ID" ]; };
      #     # token from DISCORD_BOT_TOKEN env
      #   };
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
    };
  };

  configFile = pkgs.writeText "openclaw-desired.json" (builtins.toJSON openclawConfig);
in
{
  services.caddy.proxyServices = {
    "openclaw.rocknas.local" = gatewayPort;
  };

  # ==================
  # Service user/group
  # ==================

  users.users.openclaw = {
    isSystemUser = true;
    uid = 1540;
    group = "openclaw";
    description = "OpenClaw service user";
    home = "/var/lib/openclaw";
    createHome = true;
  };

  users.groups.openclaw = {
    gid = 1540;
  };

  # ===================
  # Secrets + config injection
  # ===================
  systemd.services.docker-openclaw.preStart = ''
    mkdir -p /var/lib/openclaw/config /var/lib/openclaw/workspace
    chown -R openclaw:openclaw /var/lib/openclaw

    CONF=/var/lib/openclaw/config/openclaw.json
    if [ -f "$CONF" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$CONF" ${configFile} > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
    else
      cp ${configFile} "$CONF"
    fi
    chown openclaw:openclaw "$CONF"

    printf '%s\n' \
      "OPENCLAW_GATEWAY_TOKEN=$(cat ${config.sops.secrets.openclaw_gateway_token.path})" \
      "OPENCLAW_GATEWAY_PASSWORD=$(cat ${config.sops.secrets.openclaw_gateway_password.path})" \
      "OPENROUTER_API_KEY=$(cat ${config.sops.secrets.openrouter_api_key.path})" \
      "ANTHROPIC_API_KEY=$(cat ${config.sops.secrets.anthropic_api_key.path})" \
      "BRAVE_SEARCH_API_KEY=$(cat ${config.sops.secrets.brave_search_api_key.path})" \
      "TELEGRAM_BOT_TOKEN=$(cat ${config.sops.secrets.telegram_bot_token.path})" \
      > /run/openclaw.env
    chmod 0600 /run/openclaw.env
  '';

  # ===================
  # Containers
  # ===================
  virtualisation.oci-containers.containers = {

    openclaw = {
      image = "ghcr.io/openclaw/openclaw:latest";
      ports = [
        "${toString gatewayPort}:18789"
        "${toString bridgePort}:18790"
      ];
      volumes = [
        "/var/lib/openclaw/config:/home/node/.openclaw"
        "/var/lib/openclaw/workspace:/home/node/.openclaw/workspace"
      ];
      environment = {
        HOME = "/home/node";
        TERM = "xterm-256color";
      };
      environmentFiles = [ "/run/openclaw.env" ];
      cmd = [
        "node"
        "dist/index.js"
        "gateway"
      ];
      extraOptions = [
        "--init"
        "--user=${toString config.users.users.openclaw.uid}:${toString config.users.groups.openclaw.gid}"
      ];
      autoStart = true;
    };

    openclaw-cli = {
      image = "ghcr.io/openclaw/openclaw:latest";
      volumes = [
        "/var/lib/openclaw/config:/home/node/.openclaw"
        "/var/lib/openclaw/workspace:/home/node/.openclaw/workspace"
      ];
      environment = {
        HOME = "/home/node";
        TERM = "xterm-256color";
        BROWSER = "echo";
      };
      environmentFiles = [ "/run/openclaw.env" ];
      cmd = [
        "node"
        "dist/index.js"
      ];
      extraOptions = [
        "--init"
        "--tty"
        "--interactive"
        "--user=${toString config.users.users.openclaw.uid}:${toString config.users.groups.openclaw.gid}"
      ];
      autoStart = false;
    };
  };

  # ===================
  # Data directories
  # ===================
  systemd.tmpfiles.rules = [
    "d /var/lib/openclaw 0755 openclaw openclaw -"
    "d /var/lib/openclaw/config 0755 openclaw openclaw -"
    "d /var/lib/openclaw/workspace 0755 openclaw openclaw -"
  ];

  # ===================
  # Firewall
  # ===================
  networking.firewall.allowedTCPPorts = [
    gatewayPort
    bridgePort
  ];
  networking.firewall.allowedUDPPorts = [
    5353
  ];
}
