{
  description = "NixOS configuration for ROCK 5 ITX";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixarr = {
      url = "github:rasmus-kirk/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      sops-nix,
      nixarr,
      ...
    }@inputs:
    let
      settings = import ./settings.nix;
      system = settings.targetSystem;

      overlays = [
        (final: prev: {
          stable = import nixpkgs-stable {
            inherit system;
            config.allowUnfree = true;
          };
        })
      ];
    in
    {
      nixosConfigurations.${settings.hostName} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs settings; };
        modules = [
          { nixpkgs.overlays = overlays; }
          sops-nix.nixosModules.sops
          ./hardware-configuration.nix
          ./hosts/system/default.nix
          nixarr.nixosModules.default
        ];
      };

      nixosConfigurations."${settings.hostName}-ISO" = nixpkgs.lib.nixosSystem {
        system = settings.targetSystem;
        specialArgs = { inherit inputs settings; };
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./hardware-configuration.nix
          ./hosts/iso/default.nix
          {
            nixpkgs.crossSystem = {
              system = settings.targetSystem;
            };
            nixpkgs.localSystem = {
              system = settings.hostSystem;
            };
          }
        ];
      };

      packages.${settings.hostSystem}.iso =
        self.nixosConfigurations."${settings.hostName}-ISO".config.system.build.isoImage;
    };
}
