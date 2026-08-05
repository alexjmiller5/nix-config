{ pkgs, username, lib, ... }:

# Shared home-manager base for every host.
{
  imports = [ ./git.nix ./scripts.nix ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  home.packages = with pkgs; [
    uv
    deno
    ripgrep
    jq
    act
    bat
    d2
    fzf
    git-filter-repo
    gitleaks
    _7zz
    shellcheck
    sshpass
    tree
    yq-go
  ];
}
