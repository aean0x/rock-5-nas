{
  config,
  pkgs,
  lib,
  settings,
  ...
}:
let
  cfg = config.services.openclaw;
  openclawConfig = import ./config.nix { inherit pkgs lib settings; };
  agentDefs = openclawConfig.agentDefs;
  workspaceDefs = import ./workspace.nix { inherit lib agentDefs; };
  baseImage = "ghcr.io/phioranex/openclaw-docker:latest";
  configDir = "/var/lib/openclaw";
  workspaceDir = "${configDir}/workspace";

  # Generate env file script lines from envSecrets
  envFileScript = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      envVar: secretPath: ''echo "${envVar}=$(cat ${secretPath})" >> /run/openclaw.env''
    ) cfg.envSecrets
  );

  # Generated files for workspace assembly
  persistentIntroFile = pkgs.writeText "persistent-intro" workspaceDefs.persistentIntro;
  workspaceDocs = lib.mapAttrs (
    name: doc: pkgs.writeText "${name}-protected" doc.protected
  ) workspaceDefs.documents;
  workspaceDefaults = lib.mapAttrs (
    name: doc: pkgs.writeText "${name}-default" doc.initialPersistent
  ) workspaceDefs.documents;

  # Per-agent generated workspace files (AGENTS.md + TOOLS.md)
  subAgentFiles = lib.mapAttrs (id: def: {
    agentsMd = pkgs.writeText "${id}-AGENTS.md" def.agentsMd;
    toolsMd = pkgs.writeText "${id}-TOOLS.md" (def.toolsMd or "");
  }) agentDefs.enabledSubAgents;

  # Shell script snippet to deploy all sub-agent workspaces
  subAgentSetup = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (id: files: ''
      agent_dir="${workspaceDir}/sub-agents/${id}"
      mkdir -p "$agent_dir/memory"
      cp ${files.agentsMd} "$agent_dir/AGENTS.md"
      cp ${files.toolsMd} "$agent_dir/TOOLS.md"
      for shared in SOUL.md STYLE.md USER.md; do
        if [ -f "${workspaceDir}/$shared" ]; then
          ln -sf "../../$shared" "$agent_dir/$shared"
        fi
      done
      if [ -d "${workspaceDir}/skills" ]; then
        ln -sfn "../../skills" "$agent_dir/skills"
      fi
    '') subAgentFiles
  );

  dockerGid =
    if (config.users.groups ? docker && config.users.groups.docker.gid != null) then
      config.users.groups.docker.gid
    else
      131;
in
{
  config = {

    # Recover from in-process restarts (SIGUSR1 / /config edits)
    systemd.services.docker-openclaw-gateway.serviceConfig = {
      Restart = pkgs.lib.mkForce "always";
      RestartSec = "5s";
    };

    # Deploy config + secrets (runs once on rebuild, not on container restart)
    systemd.services.openclaw-setup = {
      description = "Deploy OpenClaw config and secrets";
      wantedBy = [ "multi-user.target" ];
      before = [ "docker-openclaw-gateway.service" ];
      requiredBy = [ "docker-openclaw-gateway.service" ];
      after = [
        "sops-nix.service"
        "openclaw-builder.service"
      ];
      requires = [ "openclaw-builder.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail
        mkdir -p ${configDir} ${workspaceDir}/memory

        # Deploy shared workspace files (e.g. USER.md, skills/, etc.)
        cp -r ${./workspace}/. "${workspaceDir}/"

        # Set base ownership (agent owns everything by default)
        chown -R 1000:1000 ${configDir}
        chmod -R 700 ${configDir}

        # Function to update managed files (AGENTS.md, SOUL.md, STYLE.md) with persistent sections
        update_doc() {
          local name="$1"
          local protected_path="$2"
          local default_persistent_path="$3"
          local target="${workspaceDir}/$name"
          local separator=$'\n\n---\n\n'

          local persistent_content=""
          # Check for existing persistent marker
          if [ -f "$target" ] && grep -Fq "${workspaceDefs.persistentMarker}" "$target"; then
             # Extract from marker line onwards
             sed -n "/${workspaceDefs.persistentMarker}/,\$p" "$target" > "$target.persistent"
          else
             # Combine intro + default content
             cat ${persistentIntroFile} "$default_persistent_path" > "$target.persistent"
          fi

          # Assemble: Protected + Separator + Persistent
          cat "$protected_path" > "$target.tmp"
          echo "$separator" >> "$target.tmp"
          cat "$target.persistent" >> "$target.tmp"

          mv "$target.tmp" "$target"
          rm -f "$target.persistent"

          # Ensure ownership by agent
          chown 1000:1000 "$target"
          chmod 0640 "$target"
        }

        # Update managed documents
        update_doc "AGENTS.md" "${workspaceDocs."AGENTS.md"}" "${workspaceDefaults."AGENTS.md"}"
        update_doc "SOUL.md"   "${workspaceDocs."SOUL.md"}"   "${workspaceDefaults."SOUL.md"}"
        update_doc "STYLE.md"  "${workspaceDocs."STYLE.md"}"  "${workspaceDefaults."STYLE.md"}"

        # Deploy sub-agent workspaces (generated from agents.nix)
        ${subAgentSetup}

        CONFIG_FILE="${configDir}/openclaw.json"
        cp ${openclawConfig.configFile} "$CONFIG_FILE"
        chown 1000:${toString dockerGid} "$CONFIG_FILE"
        chmod 0660 "$CONFIG_FILE"

        # Generate environment file from services.openclaw.envSecrets
        rm -f /run/openclaw.env
        touch /run/openclaw.env
        chmod 0640 /run/openclaw.env
        ${envFileScript}
      '';
    };

    # Weekly image refresh
    systemd.services.openclaw-refresh = {
      description = "Pull latest OpenClaw image and rebuild custom image";
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.docker}/bin/docker pull ${baseImage} || true
        ${pkgs.docker}/bin/docker image prune -f --filter "until=168h"
        ${pkgs.systemd}/bin/systemctl restart openclaw-builder.service
        ${pkgs.systemd}/bin/systemctl try-restart docker-openclaw-gateway.service
      '';
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
    };

    systemd.timers.openclaw-refresh = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon 04:00:00";
        Persistent = true;
        RandomizedDelaySec = "3600";
      };
    };
  };
}
