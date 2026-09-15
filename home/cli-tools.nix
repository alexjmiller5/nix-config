{ config, pkgs, ... }:

# Universal CLI toolbox — no personal coupling, no custom specialArgs, so it
# is exportable via homeModules (work-laptop flake imports it as-is).
# (fzf lives in zsh.nix as programs.fzf — its value is the shell integration.)
{
  imports = [
    ../modules/manual-steps.nix
    ./herdr.nix
  ];

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
    # Agent-provider quota windows (Claude, Codex, ...) - see the `quota` skill
    (callPackage ../pkgs/quota-axi.nix { })
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
    # In-buffer markdown rendering, for the frontmatter-bearing files VS Code
    # must not open (SKILL.md, AGENTS.md, memories - see dotfiles/vscode
    # settings.json). It only draws extmark decorations over the buffer and
    # never rewrites it, which is exactly what a WYSIWYG editor gets wrong.
    plugins = [ pkgs.vimPlugins.render-markdown-nvim ];
  };
  xdg.configFile."nvim/init.lua".source = ../dotfiles/nvim/init.lua;

  # Export the XDG base-dir vars ($XDG_CONFIG_HOME etc.) so tools that honor
  # them (swiftpm, less 598+, ...) stop littering $HOME with dotfiles.
  xdg.enable = true;
  # less pre-598 ignores XDG; the env var works on every version.
  home.sessionVariables.LESSHISTFILE = "${config.xdg.stateHome}/lesshst";

  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  manual.steps = {
    quota-axi-keychain = {
      title = "quota-axi Keychain grant";
      owner = "quota-axi";
      desktop = true;
      body = ''
        After the Claude Code login, run
        `quota-axi --allow-keychain-prompt` once from a desktop Terminal and click
        **Always Allow** (it asks for the login password). Claude keeps its OAuth
        token in the Keychain item "Claude Code-credentials"; that click adds
        `/usr/bin/security` to the item's ACL so `quota-axi` can read Claude quota
        silently from then on. Undeclarable: editing a Keychain ACL needs the
        login-keychain password. Until it is done every read reports
        `claude … auth_required · keychain_access_required`.
      '';
      verify = "! quota-axi --provider claude --no-credential-refresh | grep -q keychain_access_required";
      redo = "if Claude Code recreates its Keychain item (a fresh `/login` after `/logout`)";
    };
  };

}
