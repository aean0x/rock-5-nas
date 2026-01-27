{
  description = "NixOS configuration for ROCK 5 ITX";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      home-manager,
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
          ./hosts/system/hardware-configuration.nix
          ./hosts/common/kernel.nix
          ./hosts/system/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users."${settings.adminUser}" = {
              imports = [
                ./home/home.nix
              ];
            };
          }
        ];
      };

      nixosConfigurations."${settings.hostName}-ISO" = nixpkgs.lib.nixosSystem {
        system = settings.targetSystem;
        specialArgs = { inherit inputs settings; };
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
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
