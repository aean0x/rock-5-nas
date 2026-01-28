{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nano
    git
    htop
    tmux
    wget
    curl
    sops
  ];
}
