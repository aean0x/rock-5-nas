# OpenClaw agent definitions - imports shenhao-stu/openclaw-agents manifest.
# Agent IDs and roles come from the pinned repo's agents.yaml.
# Tool policies, sandbox secrets, and JSON config generation are layered on here.
#
# Structure:
#   1. YAML import & shared defaults (tools, workspace templates)
#   2. Per-agent override dicts
#   3. mkAgent config builder
{
  pkgs,
  lib,
  openclaw-agents,
}:
let
  env = name: "\${${name}}";
  hostWorkspace = "/home/node/.openclaw/workspace";

  # ── YAML Import ────────────────────────────────────────────
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  agentsJson = pkgs.runCommand "openclaw-agents-json" { nativeBuildInputs = [ python ]; } ''
        python3 -c "
    import yaml, json, sys
    raw = open('${openclaw-agents}/agents.yaml', 'rb').read().decode('utf-8', errors='replace')
    data = yaml.safe_load(raw)
    json.dump(data, sys.stdout, ensure_ascii=False)
    " > $out
  '';
  manifest = builtins.fromJSON (builtins.readFile agentsJson);
  allAgents = manifest.agents;
  subAgentList = builtins.filter (a: a.id != "main") allAgents;
  subAgentIds = map (a: a.id) subAgentList;

  # ── Agent display name (strip emoji prefix) ───────────────
  agentName =
    a:
    let
      parts = lib.splitString " " a.name;
    in
    if builtins.length parts > 1 then builtins.elemAt parts 1 else a.name;

  # ── Shared Defaults ────────────────────────────────────────
  # Sub-agents inherit all tools from agents.defaults in config.nix.
  # Overrides use deny lists to restrict, or extraAllow to explicitly grant group access.
  defaultOverrides = {
    extraAllow = [ ];
    denyTools = [ ];
    secrets = { };
    agentsMdBlurb = null;
  };

  # ── Main Agent Config ─────────────────────────────────────
  mainTools = {
    profile = "full";
    # prettier-ignore
    deny = [
      "group:web"
      "group:email"
      "group:messaging"
      "group:ui"
    ];
  };

  # ── Per-Agent Overrides ────────────────────────────────────
  # Each key maps to an agent ID. Missing agents fall back to defaultOverrides.
  # Fields:
  #   extraAllow    - additional tool grants (e.g. "group:web", "sessions_spawn")
  #   denyTools     - explicit deny list
  #   secrets       - env vars injected into sandbox
  #   agentsMdBlurb - optional markdown prepended to this agent's AGENTS.md protected section
  agentOverrides = {
    planner = {
      extraAllow = [ "sessions_spawn" ];
    };
    ideator = { };
    critic = { };
    surveyor = {
      extraAllow = [ "group:web" ];
      secrets = {
        BRAVE_API_KEY = env "BRAVE_API_KEY";
        GOOGLE_PLACES_API_KEY = env "GOOGLE_PLACES_API_KEY";
        BROWSERLESS_API_TOKEN = env "BROWSERLESS_API_TOKEN";
      };
    };
    coder = { };
    writer = { };
    reviewer = { };
    scout = {
      extraAllow = [ "group:web" ];
      secrets = {
        BRAVE_API_KEY = env "BRAVE_API_KEY";
        GOOGLE_PLACES_API_KEY = env "GOOGLE_PLACES_API_KEY";
        BROWSERLESS_API_TOKEN = env "BROWSERLESS_API_TOKEN";
      };
    };
  };

  # Merge an agent's overrides with defaults
  resolveOverrides = id: defaultOverrides // (agentOverrides.${id} or { });

  # ── Sub-Agent Workspace Templates ──────────────────────────
  subAgentWorkspace = {
    persistentMarker = "<!-- OPENCLAW-PERSISTENT-SECTION -->";
    persistentIntro = ''
      <!-- OPENCLAW-PERSISTENT-SECTION -->

      ## Personal Evolution Section (Agent-owned)

      Below this line is yours to evolve. As you learn who you are and how you work best, update this section freely.

      If you need changes to the protected section above, ask the user to update the repository baseline.

    '';
    documents = {
      "AGENTS.md" = {
        protected = ''
          ## Language: English Only
          All output in American English. Chinese in source files is reference content only. Apply STYLE.md rules to every message.

          ## Environment Context
          - You are a sub-agent. For any admin-level commands (`openclaw doctor`, gateway operations, sandbox management, config changes), reply exactly "Delegate to main" and stop.
          - Skills are shared from main to all sub-agents, mounted from `/home/node/.openclaw/workspace/skills`
          - workspace/.tools is ro mounted and in PATH for common utilities.
          - Sub-agents have full access to the same browser (Playwright), search, and tool commands as main. Use remote profile only when you specifically need stealth/different IP.
        '';
        initialPersistent = ''
          ### Notes to Future Me
          - Keep this section concise and practical.
          - Record durable process improvements, not noisy logs.
        '';
      };
    };
  };

  # ── mkAgent: Build JSON config entry for a sub-agent ───────
  mkAgent =
    { workspace, gatewayUrl }:
    a:
    let
      ovr = resolveOverrides a.id;
    in
    {
      id = a.id;
      workspace = "${workspace}/.agents/${a.id}";
      identity.name = agentName a;
      memorySearch.enabled = false;
      sandbox = {
        workspaceAccess = "rw";
        docker = {
          network = "bridge";
          setupCommand = "export PATH=\"${workspace}/.tools:\$PATH\"";
          binds = [
            "${hostWorkspace}/skills:${workspace}/.agents/${a.id}/skills:ro"
            "${hostWorkspace}/.tools:${workspace}/.tools:ro"
          ];
          env = ovr.secrets // {
            OPENCLAW_GATEWAY_TOKEN = env "OPENCLAW_GATEWAY_TOKEN";
            OPENCLAW_GATEWAY_URL = gatewayUrl;
          };
        };
      };
      tools =
        lib.optionalAttrs (ovr.extraAllow != [ ]) { allow = ovr.extraAllow; }
        // lib.optionalAttrs (ovr.denyTools != [ ]) { deny = ovr.denyTools; };
    };

in
{
  inherit
    subAgentList
    subAgentIds
    subAgentWorkspace
    agentOverrides
    resolveOverrides
    ;
  templateSrc = openclaw-agents;

  mkJsonConfig =
    { workspace, gatewayUrl }:
    let
      mainDef = {
        id = "main";
        subagents.allowAgents = [ "*" ];
        sandbox.mode = "off";
        tools = {
          profile = mainTools.profile;
          deny = mainTools.deny;
        };
      };
    in
    [ mainDef ] ++ (map (mkAgent { inherit workspace gatewayUrl; }) subAgentList);
}
