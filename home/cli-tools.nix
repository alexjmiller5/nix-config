{ config, pkgs, ... }:

# Universal CLI toolbox — no personal coupling, no custom specialArgs, so it
# is exportable via homeModules (work-laptop flake imports it as-is).
# (fzf lives in zsh.nix as programs.fzf — its value is the shell integration.)
{
  home.packages = with pkgs; [
    uv
    ripgrep
    jq
    act
    bat
    git-filter-repo
    gitleaks
    _7zz
    shellcheck
    tree
    yq-go
  ];

  # Editor everywhere: nvim, with a real `vim` shim and $EDITOR set
  # (defaultEditor). Config stays native lua in dotfiles/.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    # New 26.05 defaults, made explicit: no plugins need the providers
    withRuby = false;
    withPython3 = false;
  };
  xdg.configFile."nvim/init.lua".source = ../dotfiles/nvim/init.lua;

  # Export the XDG base-dir vars ($XDG_CONFIG_HOME etc.) so tools that honor
  # them (swiftpm, less 598+, ...) stop littering $HOME with dotfiles.
  xdg.enable = true;
  # less pre-598 ignores XDG; the env var works on every version.
  home.sessionVariables.LESSHISTFILE = "${config.xdg.stateHome}/lesshst";
}
