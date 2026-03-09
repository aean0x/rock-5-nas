# OpenClaw Module — Agent Guide

Module-specific context for the `hosts/system/openclaw/` subtree. Read alongside the repo-level `AGENTS.md`.

## Module Layout

```
openclaw/
├── default.nix        # Module entry point (imports components)
├── agents.nix         # Agent definitions & JSON config logic
├── config.nix         # Gateway config generation
├── workspace.nix      # Workspace doc templates (protected vs persistent sections)
├── image.nix          # Custom Docker image builder service
├── deployment.nix     # Setup service (deploy) & refresh timer
├── onedrive.nix       # Bidirectional rclone sync
└── workspace/         # Static assets (skills/, USER.md)
```

## Path Mapping

| Host path | Container path | Notes |
|---|---|---|
| `/var/lib/openclaw` | `/home/node/.openclaw` | Single volume mount, rw for gateway |
| `/var/lib/openclaw/openclaw.json` | `/home/node/.openclaw/openclaw.json` | Config file |
| `/var/lib/openclaw/workspace` | `/home/node/.openclaw/workspace` | Main Agent workspace |
| `.../workspace/sub-agents/*` | `.../workspace/sub-agents/*` | Sub-agent workspaces (nested) |
| `/var/run/docker.sock` | `/var/run/docker.sock` | For sandbox spawning |

Gateway env vars (`OPENCLAW_HOME`, `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH`) explicitly point to container paths. Subagent sandboxes get these via `agents.defaults.sandbox.docker.env` in `openclaw.json`.

## Container Architecture

- **openclaw-builder** (oneshot, `image.nix`) — builds `openclaw-custom:latest` from upstream base image, adds Docker CLI + uv. Runs before gateway.
- **openclaw-gateway** — main process, user `1000:1000`, `--network=host`, docker group for socket access.
- **openclaw-cli** — ephemeral `docker run` via the `oc` wrapper in `scripts.nix`. Same image, same user, same mounts.

All containers run as UID 1000 (maps to `node` inside, `user` on host). No root anywhere at runtime.

## Workspace & Config Deployment

Managed via `deployment.nix`. On rebuild/restart:
1. **Config**: Generated `openclaw.json` (from `config.nix` + `agents.nix`) overwrites `/var/lib/openclaw/openclaw.json`.
2. **Workspace**:
   - `USER.md` and `skills/` are copied from `workspace/`.
   - `AGENTS.md`, `SOUL.md`, `STYLE.md` are generated from `workspace.nix` templates.
   - **Persistence**: These 3 core docs have a "Protected" top section (repo-managed) and a "Persistent" bottom section (agent-managed). The setup script preserves the bottom section if it exists.
   - **Sub-agents**: Workspaces generated fresh from `agents.nix` definitions. `skills/` is bind-mounted read-only.

## Agent Sandbox Defaults & Key Splitting

Sandbox defaults in `openclaw.json` apply to ALL sandboxed agents unless overridden per-agent. The defaults provide:
- Config dir bind mount (ro) so sandboxes can resolve browser profiles and gateway config
- Base env vars (`HOME`, `OPENCLAW_*`) for path resolution
- Security baseline: `capDrop: ["ALL"]`, `user: "1000:1000"`, 1g memory, 1 cpu

**Per-agent tool & key profiles:**

| Agent | Tools (allow) | Keys | Deny |
|---|---|---|---|
| main | FULL (minus deny list) | All (gateway env) | `group:web`, `group:email`, `group:messaging`, `group:ui` |
| researcher | `group:web`, `read`, `group:memory` | BRAVE, BROWSERLESS, GOOGLE_PLACES | **Implicit deny (whitelist only)** |
| communicator | `group:email`, `group:messaging`, `write` | MATON, TELEGRAM | **Implicit deny (whitelist only)** |
| controller | `group:ha`, `mcp`, `read` | HA_URL, HA_TOKEN | **Implicit deny (whitelist only)** |

This is the two-key vault principle + default deny:
- **Main**: Has broad local access (files, memory, config) but is **blind** to the web/messaging/UI.
- **Sub-agents**: Have access **only** to whitelisted tools/keys. If it's not allowed, it's denied.
- **Protocol**: Sub-agents must output strict JSON (`{"result": "...", "status": "..."}`). Main parses this safely.

## Editing openclaw.json

The JSON config is generated from Nix. To edit:
1. Modify `config.nix` (gateway settings) or `agents.nix` (agent definitions).
2. Rebuild and deploy (`deploy remote-switch`).
3. The file at `/var/lib/openclaw/openclaw.json` is overwritten with the new state.

Secrets use `${ENV_VAR}` syntax — resolved by the gateway process from environment variables injected via `sops-nix` -> `/run/openclaw.env`.

## OneDrive Sync

- Runs as UID 1000, group `users` (not a GID 1000 group — that doesn't exist on host)
- Copies sops rclone config to writable temp file before running (sops path is read-only)
- Bidirectional: pulls remote → local, then pushes local → remote
- Syncs `Shared` and `Documents` folders into `workspace/onedrive/`
- 15m timer with 2m jitter, 5m delay after boot

## Upgrade & Container Refresh

`upgrade` and `remote-upgrade` trigger `refresh-containers.service` after system activation. This pulls latest images for all containers and restarts any that changed. The `openclaw-refresh` timer (Mon 04:00) independently pulls the base image, rebuilds custom, and restarts the gateway.
