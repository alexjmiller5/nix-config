{ lib, ... }:

# Git identity — shared by every host. Signing is laptop-only (needs the 1P
# desktop app) and layered on in home/macbook-air.nix. Identity uses mkDefault
# so downstream consumers (e.g. a work-laptop flake) can override the email.
{
  programs.git = {
    enable = true;
    settings.user = {
      name = lib.mkDefault "Alex Miller";
      email = lib.mkDefault "98389659+alexjmiller5@users.noreply.github.com";
    };
    # nixpkgs git ships credential.helper=osxkeychain in its SYSTEM gitconfig;
    # on a locked keychain (headless mini's launchd session, any ssh session)
    # it BLOCKS forever waiting for an unlock that never comes — this hung the
    # mini's agent-config pulls. An empty first helper resets the inherited
    # list; the per-URL helper below still applies.
    settings.credential.helper = "";

    # Default GitHub https auth for external consumers of this module (work
    # laptop etc.). Alex's machines override it with the machine-vault
    # credential helper in their per-host home files.
    settings.credential."https://github.com".helper = lib.mkDefault "!gh auth git-credential";
  };

  # Syntax-highlighted pager for git diff/log/show/blame
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options.navigate = true; # n/N jump between files in a diff
  };

  xdg.configFile."git/ignore".text = ''
    **/.claude/settings.local.json
  '';
}
