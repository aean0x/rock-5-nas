# AGENTS.md

Technical roadmap for AI agents working with this NixOS flake configuration.

## Architecture Overview

```
flake.nix                    # Entry point - three outputs: system, ISO, netboot
├── settings.nix             # All user config (hostname, network, admin user)
├── hardware-configuration.nix  # RK3588 kernel, device tree, boot params
├── deploy                   # Lean command router (sources scripts/common.sh)
├── shell.nix                # Dev shell (age, sops, rsync, dnsmasq, python3, etc.)
├── scripts/                 # All scripts (workstation + on-device)
│   ├── common.sh            # Shared: settings parsing, colors, check_ssh, build helpers
│   ├── build-iso.sh         # ISO build + USB write prompt
│   ├── build-netboot.sh     # Netboot image build only
│   ├── netboot.sh           # PXE server (dnsmasq DHCP/TFTP + HTTP), LAN or direct-connect
│   ├── install.sh           # Remote install: partition, rsync repo, nixos-install
│   └── scripts.nix          # On-device management commands (switch, help, docker-ps, oc, etc.)
├── hosts/
│   ├── system/              # Target system (what gets installed)
│   │   ├── default.nix      # Networking, SSH, users, boot loader, bluetooth
│   │   ├── packages.nix     # System-wide packages
│   │   ├── partitions.nix   # Filesystem mounts (label-based), ZFS dataset mounts
│   │   ├── tasks.nix        # Auto-upgrade (Sun 03:00) and garbage collection
│   │   ├── services.nix     # Service imports (uncomment to enable)
│   │   ├── containers.nix   # Docker engine, refresh timer, imports containers/* + openclaw
│   │   ├── containers/      # Docker container modules
│   │   │   ├── home-assistant.nix # Home Assistant, Matter Server, OTBR
│   │   │   └── filebrowser.nix    # Web-based file manager (SOPS-managed admin password)
│   │   ├── openclaw/         # OpenClaw gateway, workspace dotfiles, related services
│   │   │   ├── default.nix        # Docker containers, builder, setup, refresh timer
│   │   │   ├── agents.nix         # Agent definitions (tools, secrets, docs, enable flags)
│   │   │   ├── config.nix         # Gateway config as Nix attrset (generates openclaw.json)
│   │   │   ├── onedrive.nix       # OneDrive bidirectional sync into workspace
│   │   │   └── workspace/         # Static shared dotfiles deployed to /var/lib/openclaw/workspace/
│   │   │       ├── AGENTS.md      # Ops content (session, memory, safety, heartbeats) — roles appended from agents.nix
│   │   │       ├── SOUL.md        # Personality directives
│   │   │       └── STYLE.md       # Message formatting and output rules
│   │   └── services/        # Native service modules
│   │       ├── tailscale.nix      # Tailscale VPN (native NixOS)
│   │       ├── adguard.nix        # AdGuard Home DNS (native NixOS)
│   │       ├── cloudflared.nix    # Cloudflare tunnel (native NixOS)
│   │       ├── remote-desktop.nix # XFCE + xrdp
│   │       └── caddy.nix         # Reverse proxy with ACME DNS-01 via Cloudflare
│   └── iso/                  # Installer image (shared by ISO + netboot)
│       ├── default.nix       # Minimal env: SSH + pubkeys + avahi + rsync (no secrets)
│       ├── iso.nix           # ISO-specific config (isoImage settings)
│       └── netboot.nix       # Netboot-specific config (placeholder)
└── secrets/                 # SOPS-encrypted secrets
    ├── sops.nix             # Secrets module (conditional WiFi, mkIf guards)
    ├── secrets.yaml         # Encrypted secrets (committed)
    ├── secrets.yaml.example # Template for new users
    ├── encrypt              # Key generation + encryption workflow
    └── decrypt              # Decrypt for editing
```

## Key Patterns

### Settings vs Secrets

**settings.nix** — Values needed at Nix eval time:
- `repoUrl` — Single string "owner/repo" for flake references
- `hostName`, `adminUser`, `setupPassword` — Must be known at build time
- `domain` — Public domain for ACME certs (subdomains defined per-service)
- `network` — Static IP config (interface, address, prefixLength, gateway, DNS)
- `enableWifi`, `wifiSsid` — Optional WiFi (PSK is a secret)
- Build systems (`hostSystem`, `targetSystem`) for cross-compilation
- `kernelPackage` — Kernel version (6.18 for rk3588)
- Service ports live in their respective modules as `let` bindings

**secrets/sops.nix** — Runtime secrets (decrypted at activation):
- `user_hashedPassword` — Login password
- `tailscale_authKey` — Tailscale auth key
- `wifi_psk` — WiFi password (conditional on `settings.enableWifi`)
- `openclaw_gateway_token`, `openclaw_gateway_password` — OpenClaw gateway auth
- `xai_api_key` — xAI/Grok model API key
- `openrouter_api_key`, `anthropic_api_key` — LLM provider keys
- `brave_search_api_key`, `google_api_key`, `google_places_api_key` — Search/maps
- `browserless_api_token` — Remote browser CDP service
- `telegram_bot_token`, `telegram_admin_id` — Telegram bot + admin allowlist
- `maton_api_key` — Email/messaging integration
- `ha_token`, `ha_url` — Home Assistant API
- `cloudflare_dns_api_token` — Cloudflare API for ACME DNS-01 challenge
- `filebrowser_password` — FileBrowser admin password
- `onedrive_rclone_config` — rclone config for OneDrive sync (mode 0444)
- `cloudflared_tunnel_credentials` — Cloudflare tunnel JSON (conditional, owned by cloudflared user)

### Service Architecture

Philosophy: **Docker for complex/dependency-heavy stacks, native NixOS for simple/well-supported services.**

| Service | Type | Module | Notes |
|---------|------|--------|-------|
| Docker engine | Native | `containers.nix` | Auto-prune, unified refresh timer |
| Home Assistant + Matter + OTBR | Docker | `containers/home-assistant.nix` | Host network for mDNS/Thread |
| FileBrowser | Docker | `containers/filebrowser.nix` | Web file manager for OpenClaw state |
| OpenClaw gateway + CLI | Docker | `openclaw/default.nix` | Custom image, sandbox spawner |
| Tailscale VPN | Native | `services/tailscale.nix` | |
| AdGuard Home DNS | Native | `services/adguard.nix` | Port 53 + web UI 3000 |
| Caddy | Native | `services/caddy.nix` | Reverse proxy, Cloudflare ACME |
| Remote Desktop | Native | `services/remote-desktop.nix` | XFCE + xrdp |

Disabled but available: Cockpit, Cloudflared, arr-suite, Transmission.

**containers.nix** is pure infrastructure — Docker engine, auto-prune, unified `refresh-containers` timer. Container definitions live in their respective modules. `containerNames` and `uniqueImages` are auto-discovered from all imported modules. The single `refresh-containers` timer (Sun 02:00) pulls all images and restarts all containers.

### Docker Network Patterns

- **Host network** (`--network=host`): Used by HA, Matter, OTBR, OpenClaw gateway for mDNS/multicast discovery
- **Bridge network**: Used by OpenClaw sandbox containers (connects to gateway via `ws://172.17.0.1:18789`)

### Env Injection Pattern

Docker containers needing sops secrets use a separate oneshot service (runs before container) to:
1. Read secrets from sops paths (`cat ${config.sops.secrets.*.path}`)
2. Write env files to `/run/<name>.env` (mode 600/640)
3. Container references via `environmentFiles = [ "/run/<name>.env" ]`

Examples: `openclaw-setup` writes `/run/openclaw.env`, `caddy-env` writes `/run/caddy.env`.

### OpenClaw Docker Architecture

OpenClaw lives in `hosts/system/openclaw/` as a self-contained module. Two Docker containers (`openclaw-gateway` + `openclaw-cli`) using a custom image built on-device. Runs non-root as UID 1000. State at `/var/lib/openclaw/` mounted to `/home/node/.openclaw` inside containers.

- **`openclaw-builder`** (oneshot) — builds `openclaw-custom:latest` from upstream `ghcr.io/phioranex/openclaw-docker:latest`. Adds: Docker CLI (static aarch64 binary), uv (direct tarball to `/usr/local/bin`), git, curl, jq, nodejs, python3-pip, build-essential. Runs before gateway via `requiredBy`.
- **`openclaw-setup`** (oneshot) — deploys workspace dotfiles from Nix store, creates sub-agent directories with relative symlinks to shared files (SOUL.md, STYLE.md, USER.md), copies `openclaw.json` with secret substitution, writes `/run/openclaw.env` with all API keys.
- **Gateway container** — `--network=host`, `--group-add=docker` for docker.sock access. Spawns sandbox containers for sub-agents. Restart policy: always (recovers from SIGUSR1 self-restart).
- **CLI container** (`oc` command) — ephemeral `docker run --rm`, same image and mounts, for ad-hoc CLI commands.
- **Config as Nix**: `config.nix` defines the full gateway config as a Nix attrset, generated to JSON via `builtins.toJSON`. Imports agent definitions from `agents.nix`. Nix-evaluable values (domain, port) are inlined at build time. Secret placeholders (`${VAR}`) remain as literal strings — OpenClaw resolves them from process env at runtime. `openclaw-setup` copies the generated JSON to `/var/lib/openclaw/openclaw.json` (mutable — OpenClaw can write runtime changes; overwritten on rebuild).
- **Agent definitions**: `agents.nix` is the single source of truth for all agents. Each agent definition carries: tools config (allow/deny), sandbox secrets, role description, AGENTS.md content, TOOLS.md content, and an `enable` flag. Disabled agents are excluded from both JSON config and workspace generation. The main AGENTS.md delegation section is generated dynamically from enabled agents.
- **Workspace generation**: `workspace/` contains static shared files (SOUL.md, STYLE.md, AGENTS.md ops content). Setup assembles the final main AGENTS.md by concatenating static ops content + generated role profiles from `agents.nix`. Sub-agent directories are created dynamically with generated AGENTS.md, TOOLS.md, and relative symlinks to shared files.
- **Sandbox architecture** — gateway spawns sandbox containers via mounted `docker.sock`. Default sandbox config: bridge network, readOnlyRoot, capDrop ALL, 1 CPU. Per-agent env overrides inject only the API keys each role needs (two-key vault principle). Browser enabled with `allowHostControl` for host Browserless CDP proxy.
- **OneDrive sync** — `onedrive.nix` (imported by openclaw module) runs bidirectional rclone copy on a 15m timer as UID 1000. Syncs `Shared` and `Documents` into `workspace/onedrive/`.
- **`openclaw-refresh`** timer (Mon 04:00) — pulls latest base image, rebuilds custom image, restarts gateway.

### Caddy Reverse Proxy

Custom NixOS option `services.caddy.proxyServices` maps hostnames to backend ports. Each entry auto-generates:
- HTTP vhost with redirect to HTTPS
- HTTPS vhost with Cloudflare DNS-01 TLS and `reverse_proxy` to localhost

Uses `caddy-dns/cloudflare` plugin built via `pkgs.caddy.withPlugins`. Root domain routes to Home Assistant. Service modules register their own subdomains (e.g., `services.caddy.proxyServices."openclaw.${settings.domain}" = 18789`).

### ZFS Pool

Single pool mounted at `/media` with `nofail` + `zfsutil` (boot succeeds even if pool doesn't exist):

Manual pool creation on first boot:
```bash
zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -O mountpoint=/media media mirror /dev/disk/by-id/<disk1> /dev/disk/by-id/<disk2>
```

### Flake Outputs

- `nixosConfigurations.${hostName}` — Main system (what gets installed)
- `nixosConfigurations.${hostName}-ISO` — ISO installer image
- `nixosConfigurations.${hostName}-netboot` — Netboot installer image
- `packages.${hostSystem}.iso` — ISO build artifact
- `packages.${hostSystem}.netboot` — Netboot build artifact (kernel, initrd, snp.efi, netboot.ipxe)

ISO and netboot share `installerModules` (cross-compilation config + `hosts/iso/default.nix`). ISO-specific config in `hosts/iso/iso.nix`, netboot-specific in `hosts/iso/netboot.nix`.

### Container Exec (auto-derived)

Container wrapper scripts are auto-generated from `config.virtualisation.oci-containers.containers` in `scripts.nix`:
- Each container gets a shell command: `<name>` shells in, `<name> <cmd>` runs a command
- `help` auto-lists available containers
- `deploy` catches unrecognized commands and passes through via SSH (device-side wrappers handle them)

### SSH Resolution

`check_ssh` in `common.sh` resolves the device once and sets `TARGET` + `SSH_OPTS` for the entire session:
1. Try `${ADMIN}@${HOST}.local` (mDNS) with key auth
2. Try `${ADMIN}@${IP}` (static IP from settings) with key auth
3. Prompt for manual IP, try with key auth
4. Retry all candidates with password auth (for fresh installer/netboot)

All subsequent ssh/scp/rsync calls use `$TARGET` and `$SSH_OPTS` — no redundant resolution.

**Remote interaction policy:** agents should interact with the server via `./deploy` as first choice (handles discovery, SSH options, command wrapping). Direct `ssh` is acceptable when necessary. Server is ARM64 based with limited resources — prefer `remote-switch` for rebuilds. When pulling logs, cap output (default `--tail 100` or `-n 100`).

### Installation Flow

Fully remote from workstation — two boot options:
1. **USB ISO**: `./deploy build-iso` — builds pure ISO, offers to write to USB
2. **PXE netboot**: `./deploy build-netboot` then `./deploy netboot` — starts PXE server with LAN proxy or direct-connect mode

Then:
3. `./deploy install` — SSH in, partition (GPT: 512M EFI + ext4 root), rsync repo + SOPS key, nixos-install from local flake
4. Reboot — device is fully operational, sops-nix decrypts secrets on first boot
5. Subsequent updates: `./deploy remote-switch` or on-device `switch`

### PXE Netboot

Boot chain: dnsmasq(DHCP+TFTP) -> snp.efi(iPXE) -> HTTP(kernel+initrd)

Two network modes:
- **LAN proxy** — workstation and device on the same router. dnsmasq acts as DHCP proxy.
- **Direct connect** — ethernet cable between workstation and device. Full DHCP server on 192.168.100.0/24.

After netboot completes, plug device into router for WAN access before running `./deploy install`.

### SOPS Flow
1. `secrets/encrypt` generates age key if missing, handles fork detection
2. `secrets/decrypt` decrypts for editing
3. `./deploy install` copies key to `/var/lib/sops-nix/key.txt` during installation
4. System decrypts secrets at activation time (first real boot)
5. During `nixos-install`, "password file not found" warnings are expected — secrets materialize on boot

### Remote Flake Workflow
1. Edit config on dev machine, commit, push
2. On NAS: run `switch` (fetches latest config from `github:owner/repo#hostname`)
3. Auto-upgrade runs weekly (Sunday 3AM) if `tasks.nix` is enabled — updates nixpkgs inputs too
4. Or from workstation: `./deploy remote-switch` (builds locally, pushes closure)

**switch vs upgrade:**
- `switch` / `remote-switch` — fetch latest config commit, rebuild with existing flake.lock inputs
- `upgrade` / `remote-upgrade` — same + update nixpkgs/flake inputs + refresh container images

## Modification Guidelines

### Adding Secrets
1. Add key to `secrets/sops.nix` secrets block (use `lib.mkIf` for conditional secrets)
2. Add placeholder to `secrets.yaml.example`
3. Run `./secrets/decrypt` → edit → `./secrets/encrypt`
4. Reference as `config.sops.secrets."key".path` in modules

### Enabling Services
1. Uncomment the import line in `hosts/system/services.nix`
2. Ensure required secrets are configured (check service file for `config.sops.secrets.*` references)
3. Commit, push, rebuild

### Adding Docker Containers
1. Create a new module in `hosts/system/containers/`
2. Define containers under `virtualisation.oci-containers.containers`
3. Add firewall ports in the same module
4. Add import to `containers.nix`
5. Container exec wrapper and refresh timer auto-include (no manual step)

### Adding Native Services
1. Create a new module in `hosts/system/services/`
2. Use the NixOS module system (`services.<name>.enable = true`)
3. Reference sops secrets via `config.sops.secrets.*`
4. Add import line to `services.nix`

## Gotchas

- ISO/netboot build requires aarch64 support (binfmt/qemu or remote builder) since target is aarch64
- `adminUser` cannot move to SOPS (needed at Nix eval time for attribute name)
- Static IP is used (no NetworkManager) — `useDHCP = false` in system config, `useDHCP = true` in installer
- Services toggled in `hosts/system/services.nix` by uncommenting imports
- Kernel 6.18 is required for rk3588 — builds are slow due to cross-compilation
- sops-nix warnings during `nixos-install` are normal — secrets materialize on first real boot
- ZFS dataset mounts use `nofail` — boot succeeds even if pool isn't created yet
- `services.resolved.enable = false` in adguard.nix — systemd-resolved conflicts with port 53
- Cloudflared credentials must be owned by `cloudflared` user/group (set in sops.nix)
- Docker containers with static tags (`:latest`, `:stable`) are NOT re-pulled on rebuild — the unified `refresh-containers` timer (Sun 02:00) and per-service refresh timers handle image updates
- OpenClaw sandbox containers connect to gateway via Docker bridge IP (`172.17.0.1`), not localhost — containers on bridge network can't reach host loopback
- OpenClaw workspace symlinks must be relative (not absolute host paths) for container path portability
- Persistent settings go in `/var/lib` — both for native services and Docker container volume mounts
