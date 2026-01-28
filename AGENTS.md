# AGENTS.md

Technical roadmap for AI agents working with this NixOS flake configuration.

## Architecture Overview

```
flake.nix                    # Entry point - two outputs: system config + ISO builder
├── settings.nix             # Centralized config (hostname, user, SSH keys, SOPS paths)
├── hosts/
│   ├── common/              # Shared kernel config (RK3588 device tree, modules)
│   ├── system/              # Target system (what gets installed)
│   │   ├── default.nix      # Boot, networking, users, SSH - imports services/*
│   │   ├── partitions.nix   # ZFS config with auto-snapshot/scrub/trim
│   │   ├── hardware-configuration.nix  # Generated during install
│   │   └── services/        # Optional modules (all currently commented out in default.nix)
│   └── iso/                  # Installer image
│       ├── default.nix      # Cross-compilation setup, SOPS key injection
│       └── install.nix      # Derivation wrapping the installer script
├── home/                    # home-manager config
│   ├── home.nix             # User packages, shell, neovim, bin scripts
│   └── bin/                 # Management scripts deployed to ~/.local/bin
└── secrets/                 # SOPS-encrypted secrets (age encryption)
```

## Build Targets

The flake exposes:
- `nixosConfigurations.${hostName}` - Target system (aarch64-linux)
- `nixosConfigurations.${hostName}-ISO` - Installer ISO (cross-compiled from x86_64)
- `packages.x86_64-linux.iso` - Convenience alias for ISO

Build commands:
- `./build-iso.sh` - Sets up SOPS key, builds ISO with `--impure` (required for key injection)
- `nix build .#nixosConfigurations.rock5-nas.config.system.build.toplevel` - Direct system build

## Key Patterns

### Settings Propagation
`settings.nix` is imported directly (not as a module) and passed via `specialArgs`. Access with `{ settings, ... }:` in any module.

### Cross-Compilation
ISO build uses `nixpkgs.crossSystem`/`localSystem` to build aarch64 from x86_64. Certain features disabled during cross-compile (git, documentation).

### SOPS Key Injection
`build-iso.sh` exports `KEY_FILE_PATH` → `iso/default.nix` reads via `builtins.getEnv` → activation script writes to `/var/lib/sops-nix/key.txt` in ISO.

### Device Tree Handling
Kernel config (`kernel.nix`) enables DT and copies DTB to EFI partition. Boot loader config (`system/default.nix`) also copies DTB to EFI. The `rk3588-rock-5-itx.dtb` path is critical.

### Services Pattern
Services in `hosts/system/services/` are standalone modules. Enable by uncommenting imports in `hosts/system/default.nix`. Each handles its own packages, systemd units, and config.

## Modification Guidelines

### Adding a New Service
1. Create `hosts/system/services/myservice.nix`
2. Import in `hosts/system/default.nix`
3. If service needs secrets, add to `settings.nix` sops.secrets and `secrets.yaml.example`

### Adding Secrets
1. Add key path to `settings.nix` → `sops.secrets`
2. Add placeholder to `secrets.yaml.example`
3. Run `./secrets/decrypt.sh`, edit `secrets.yaml.work`, run `./secrets/encrypt.sh`
4. Reference as `config.sops.secrets."path.to.secret".path` in modules

### Kernel Changes
All in `hosts/common/kernel.nix`. The `extraConfig` mechanism adds kernel config options. `initrd.availableKernelModules` lists modules available early. `kernelParams` for boot args.

### User Management
Admin user defined in `settings.nix`, created in `hosts/system/default.nix`. Home-manager config in `home/home.nix`. Additional users would follow same pattern.

## Installation Flow

1. `build-iso.sh` → ISO with embedded SOPS key
2. Boot ISO, run `sudo nixinstall`
3. Installer partitions (GPT, optional EMMC boot), formats (vfat EFI, ext4 root)
4. Clones repo to `/tmp` and `~/.dotfiles`
5. Generates hardware-configuration.nix
6. Copies SOPS key to target
7. Builds and installs system
8. Post-install: use `rebuild` script for updates

## Common Tasks

| Task | Command/Action |
|------|----------------|
| Rebuild after config change | `rebuild` (or `rebuild -r` to reboot) |
| Update flake inputs | `rebuild -u` |
| Edit secrets | `cd secrets && ./decrypt.sh` → edit → `./encrypt.sh` |
| Enable a service | Uncomment import in `hosts/system/default.nix` |
| Change kernel version | Modify `kernelOverride` in `kernel.nix` |
| Add user package | Add to `home.packages` in `home/home.nix` |
| Add system package | Add to `environment.systemPackages` in `hosts/system/default.nix` |

## Gotchas

- ISO build requires `--impure` due to `builtins.getEnv`
- ZFS support requires `hostId` in settings (generate with `head -c 8 /etc/machine-id`)
- Kernel pinned to 6.18
- `hashedPassword` in secrets must be generated with `mkpasswd -m SHA-512`
- Hardware config is generated fresh during install; don't manually edit the committed version
- Services use `config.sops.secrets."...".path` to get file path, not the secret value directly