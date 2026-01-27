{
  pkgs,
  lib,
  ...
}:
let
  settings = import ../settings.nix;
in
{
  home = {
    username = settings.adminUser;
    homeDirectory = lib.mkForce "/home/${settings.adminUser}";
    stateVersion = "25.11";
  };

  home.packages = with pkgs; [ git ];

  programs = {
    fzf.enable = true;
    home-manager.enable = true;
    bash = {
      enable = true;
      initExtra = ''
        export PATH=$PATH:$HOME/.local/bin
      '';
    };
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
    };
  };

  home.file =
    lib.foldl'
      (
        acc: file:
        acc
        // {
          "${file.target}" = {
            source = file.source;
            executable = file.executable;
          };
        }
      )
      { }
      [
        {
          source = ./bin/rebuild;
          target = ".local/bin/rebuild";
          executable = true;
        }
        {
          source = ./bin/cleanup;
          target = ".local/bin/cleanup";
          executable = true;
        }
      ];
}
