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
    # GitHub https auth rides gh's login — no PAT in the keychain to recreate
    # by hand; `gh auth login` once and every private clone (incl. the
    # companion-repos activation) works.
    settings.credential."https://github.com".helper = "!gh auth git-credential";
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
