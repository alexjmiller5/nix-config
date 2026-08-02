{ pkgs, username, lib, ... }:

# Shared home-manager base for every host.
{
  imports = [ ./git.nix ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  home.packages = with pkgs; [
    uv
    deno
    ripgrep
    jq
    # First brew→nixpkgs tranche (2026-08-01): pure CLI tools with no macOS
    # quirks; their brew formulae are undeclared so zap removes the dupes.
    act
    bat
    d2
    fzf
    git-filter-repo
    gitleaks
    _7zz       # brew "sevenzip"
    shellcheck
    sshpass
    tree
    yq-go      # brew "yq" is mikefarah's Go yq, matching this
    # osxphotos (Apple Photos CLI) is not in nixpkgs; uvx runs it ephemerally
    # from PyPI (cached), so this wrapper is the whole install.
    (writeShellScriptBin "osxphotos" ''exec ${uv}/bin/uvx osxphotos "$@"'')
  ];
}
