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
  };

  xdg.configFile."git/ignore".text = ''
    **/.claude/settings.local.json
  '';
}
