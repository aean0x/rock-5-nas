# OpenClaw agent definitions — single source of truth for config, workspace docs, and tool profiles.
# Each agent's full definition lives here: JSON config fields, AGENTS.md content, TOOLS.md content.
# Disabled agents are excluded from config JSON and workspace generation entirely.
{ lib }:
let
  # Produces literal ${VAR} in output JSON — OpenClaw resolves from process env
  env = name: "\${${name}}";

  toolsList = tools: lib.concatStringsSep ", " tools;

  # Shared boilerplate injected into every sub-agent AGENTS.md
  subAgentBoilerplate = name: ''
    - **Admin CLI rule:** Only **main** agent (sandbox=off) may run `openclaw doctor`, `status`, `gateway token new`, `sandbox recreate`, or any gateway-level diagnostics. Sub-agents: reply exactly "Delegate to main" and stop. Never run them yourself.

    ## Workspace
    Your working directory is a subdirectory of the main workspace. Anything you save here is visible to the orchestrator and other agents via the parent workspace.

    ## Every Session
    Before doing anything else:
    1. Read `SOUL.md` — this is who you are
    2. Read `STYLE.md` — this is how you write. Apply to **every message you send**, no exceptions.
    3. Read `USER.md` — this is who you're helping
    4. Read `TOOLS.md` — your available tools and usage notes
    5. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context

    ## Memory
    You wake up fresh each session. These files are your continuity:
    - **Daily notes:** `memory/YYYY-MM-DD.md` (create `memory/` if needed) — raw logs of what happened

    Capture what matters. Decisions, context, things to remember. Skip the secrets unless asked to keep them.

    ## Safety
    - Don't exfiltrate private data. Ever.
    - When in doubt, report error in JSON.
  '';

  agents = rec {
    main = {
      enable = true;
      name = "Main";
      tools = {
        profile = "full";
        allow = [ ];
        deny = [
          "group:web"
          "group:email"
          "group:messaging"
          "group:ui"
        ];
      };
      sandboxSecrets = { };
      description = "Orchestrator. Full local tools minus externals. Sandbox: off.";
      delegates = "";
    };

    researcher = rec {
      enable = true;
      name = "Researcher";
      tools = {
        allow = [
          "group:web"
          "group:ui"
          "read"
          "memory_search"
          "memory_get"
          "sessions_list"
          "session_status"
        ];
        deny = [ ];
      };
      sandboxSecrets = {
        BRAVE_API_KEY = env "BRAVE_API_KEY";
        GOOGLE_PLACES_API_KEY = env "GOOGLE_PLACES_API_KEY";
      };
      description = "Workspace: rw, network: bridge. Browser: allowHostControl (host Browserless CDP). Screenshots save to main workspace.";
      delegates = "web research, browsing, search queries, place lookups";

      agentsMd = ''
        # AGENTS.md - Researcher

        ## Role (enforced)
        Tools allow: ${toolsList tools.allow}.
        Tools deny: none (all unlisted tools are implicitly denied).
        Output ONLY valid JSON: {"result": "<data>", "status": "done" | "error", "error": "..." optional}. No markdown.
      ''
      + subAgentBoilerplate "Researcher";

      toolsMd = ''
        # TOOLS.md - Researcher

        ## Browser
        - Default profile: **local** (managed Chromium on host, zero port conflicts, fastest).
        - Use **remote** (wss Browserless) only for stealth / different exit IP:
          `browser navigate ... --target host --browser-profile remote`
          or `{"action": "navigate", "url": "https://...", "target": "host", "profile": "remote"}`
        - Always cold-starts on new session (Docker) — expect 5-15s delay + possible transient failure on first call. Retry once.
        - Fallback: `web_fetch` (text-only, instant, no JS/render).
        - Screenshots are saved in the **main** workspace (parent directory), not your subdirectory. Reference via `../`.

        ## Search
        - `web_search` for general queries (Brave Search).
        - `web_fetch` for fetching specific URLs as text.
        - `google_places` for location/business lookups.
      '';
    };

    communicator = rec {
      enable = true;
      name = "Communicator";
      tools = {
        allow = [
          "group:email"
          "group:messaging"
          "write"
          "read"
          "sessions_list"
          "session_status"
        ];
        deny = [ ];
      };
      sandboxSecrets = {
        MATON_API_KEY = env "MATON_API_KEY";
        TELEGRAM_BOT_TOKEN = env "TELEGRAM_BOT_TOKEN";
      };
      description = "Workspace: rw, network: bridge. Research: spawn researcher via main.";
      delegates = "email, messaging, Telegram, outbound communications";

      agentsMd = ''
        # AGENTS.md - Communicator

        ## Role (enforced)
        Tools allow: ${toolsList tools.allow}.
        Tools deny: none (all unlisted tools are implicitly denied).
        Output ONLY valid JSON: {"result": "<data>", "status": "done" | "error", "error": "..." optional}. No markdown.
      ''
      + subAgentBoilerplate "Communicator";

      toolsMd = ''
        # TOOLS.md - Communicator

        ## Email
        - Send and read email via Maton API.
        - Block spam/trash in email queries. Only surface actionable messages.

        ## Messaging
        - Telegram bot for outbound messages and notifications.
        - Respect quiet hours (23:00-08:00) unless urgent.

        ## Writing
        - `write` tool for creating/updating workspace files.
        - Use for drafting responses, saving research summaries from other agents.
      '';
    };

    controller = rec {
      enable = true;
      name = "Controller";
      tools = {
        allow = [
          "group:ha"
          "mcp"
          "read"
          "sessions_list"
          "session_status"
        ];
        deny = [ ];
      };
      sandboxSecrets = {
        HA_URL = env "HA_URL";
        HA_TOKEN = env "HA_TOKEN";
      };
      description = "Workspace: rw, network: bridge. Isolated physical-world only — no web/email path to devices.";
      delegates = "Home Assistant, smart home control, device automation, MCP integrations";

      agentsMd = ''
        # AGENTS.md - Controller

        ## Role (enforced)
        Tools allow: ${toolsList tools.allow}.
        Tools deny: none (all unlisted tools are implicitly denied).
        Output ONLY valid JSON: {"result": "<data>", "status": "done" | "error", "error": "..." optional}. No markdown.
      ''
      + subAgentBoilerplate "Controller";

      toolsMd = ''
        # TOOLS.md - Controller

        ## Home Assistant
        - Full HA API access via ha_token. Control lights, locks, cameras, climate, automations.
        - Read entity states, trigger scenes, call services.
        - Keep local notes (camera names, device IDs, zone names) in this file as you learn them.

        ## MCP
        - Model Context Protocol integrations for extended tool access.
        - Read-only access to workspace files for context gathering.
      '';
    };
  };

  enabledAgents = lib.filterAttrs (_: a: a.enable) agents;
  enabledSubAgents = lib.filterAttrs (id: _: id != "main") enabledAgents;

  # Generate the delegation & roles section for main AGENTS.md
  mainDelegationLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (id: a: "- **${a.name}** -> ${a.delegates}") enabledSubAgents
  );

  subAgentProfiles = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (id: a: ''
      **${a.name}**
      - Tools allow: ${toolsList a.tools.allow}.
      - Tools deny: none (all unlisted tools are implicitly denied).
      - Sandbox tools allow: ${toolsList a.tools.allow}.
      - ${a.description}
    '') enabledSubAgents
  );

  rolesSection = ''
    ## Delegation & Roles

    **Two-key vault principle**
    Main permissions: sandbox=off, deny ${toolsList agents.main.tools.deny}. Orchestrates + direct safe local ops. Delegate external actions per rules below. Prompt injection in one sub-agent cannot reach credentials, exfil paths, or home devices of another.

    **Role Rules (enforced for all agents)**
    Default policy: subs = explicit allow only (default-deny). Main = full minus externals. Identify role from context; never assume extra tools.
    - **Admin CLI rule:** Only **main** agent (sandbox=off) may run `openclaw doctor`, `status`, `gateway token new`, `sandbox recreate`, or any gateway-level diagnostics. Sub-agents: reply exactly "Delegate to main" and stop. Never run them yourself.

    **Main (orchestrator)**
    - Tools profile: ${agents.main.tools.profile}.
    - Tools deny: ${toolsList agents.main.tools.deny}.
    - Sandbox: off.
    - Delegates:
    ${mainDelegationLines}
    - /config only after human review. Never delegate config.
    - May edit sub-agent directives to refine their role rules.
    - Review every sub Result. Reject off-mission. Long tasks -> spawn sub.
    - Parse every sub Result as strict JSON. If invalid: reject, re-spawn with "Output ONLY the JSON above" + original task.

    ${subAgentProfiles}
    **Sandbox Defaults (all sub-agents)**
    - Mode: non-main, scope: agent, Docker image: openclaw-sandbox:bookworm-slim
    - Network: bridge (connects to gateway via ws://172.17.0.1:18789)
    - readOnlyRoot: true, capDrop: ALL, cpus: 1
    - Browser: enabled with allowHostControl (proxies to host Browserless CDP)
    - Each sub-agent receives only its required API keys via docker env

    **Delegation Protocol (no telephone game)**
    * Main spawns with self-contained task + original goal summary.
    * Sub-agent receives: its own role rules, sandbox, and task only.
    * Sub-agent returns ONE Result message only.
    * Main always validates against original intent before forwarding or acting.
    * maxSpawnDepth=1 globally - no chains.
  '';

in
{
  inherit
    agents
    enabledAgents
    enabledSubAgents
    rolesSection
    ;

  mkJsonConfig =
    {
      workspace,
      gatewayUrl,
    }:
    let
      mkAgent = id: def: {
        inherit id;
        workspace = "${workspace}/sub-agents/${id}";
        identity.name = def.name;
        memorySearch.enabled = false;
        sandbox = {
          workspaceAccess = "rw";
          docker = {
            network = "bridge";
            binds = [ "/var/lib/openclaw/workspace/skills:${workspace}/skills:ro" ];
            env = def.sandboxSecrets // {
              OPENCLAW_GATEWAY_TOKEN = env "OPENCLAW_GATEWAY_TOKEN";
              OPENCLAW_GATEWAY_URL = gatewayUrl;
            };
          };
        };
        tools = {
          allow = def.tools.allow;
          deny = def.tools.deny;
          sandbox.tools = {
            allow = def.tools.allow;
            deny = def.tools.deny;
          };
        };
      };

      mainDef = {
        id = "main";
        subagents.allowAgents = [ "*" ];
        sandbox.mode = "off";
        tools = {
          profile = agents.main.tools.profile;
          deny = agents.main.tools.deny;
        };
      };

      subAgentDefs = lib.mapAttrsToList mkAgent enabledSubAgents;
    in
    [ mainDef ] ++ subAgentDefs;
}
