{ pkgs, ... }:

# Universal CLI toolbox — no personal coupling, no custom specialArgs, so it
# is exportable via homeModules (work-laptop flake imports it as-is).
{
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
