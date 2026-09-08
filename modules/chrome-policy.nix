{
  pkgs,
  lib,
  config,
  username,
  ...
}:

# Chrome enterprise policy, declared. macOS Chrome honors policy as
# MANDATORY only from /Library/Managed Preferences (root-owned); the same
# keys in the user's defaults domain land as "Recommended" (visible on
# chrome://policy, ignored for things like ExtensionInstallForcelist), so
# the plist is written by a root activation script, never system.defaults.
# Chrome reloads policy on restart (chrome://policy → Reload policies to
# force it); a policy-installed extension lands a minute or two later.
#
# Delivery: macOS's ManagedClient REBUILDS /Library/Managed Preferences from
# installed configuration profiles ~30s after every boot/login (a Screen Time
# internal profile is enough to trigger it), deleting anything not backed by
# a profile — including this plist. So a root LaunchDaemon re-copies it at
# boot and whenever that directory changes (WatchPaths), and the activation
# script uses the same install step so a switch applies it immediately.
#
# What goes in the plist is the host's business (hosts/macbook-air-chrome-
# policy.nix carries the laptop's extension set + PWAs); other modules add
# to `settings` too (services.agent-chrome.extensions).
let
  cfg = config.chrome.policy;
  chromePolicy = pkgs.writeText "com.google.Chrome.policy.plist" (
    lib.generators.toPlist { escape = true; } cfg.settings
  );
  # cmp guard: the daemon's own cp would otherwise re-fire WatchPaths forever.
  install = pkgs.writeShellScript "chrome-policy-install" ''
    dir='/Library/Managed Preferences/${username}'
    dst="$dir/com.google.Chrome.plist"
    /bin/mkdir -p "$dir"
    /usr/bin/cmp -s ${chromePolicy} "$dst" && exit 0
    /bin/cp -f ${chromePolicy} "$dst"
    /bin/chmod 644 "$dst"
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';
in
{
  options.chrome.policy = {
    enable = lib.mkEnableOption "Chrome policy via /Library/Managed Preferences";

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Chrome policy keys (chrome://policy names), serialized to the managed plist. Attrsets merge across modules.";
    };

    file = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = chromePolicy;
      description = "The generated plist, for inspection (`nix build .#darwinConfigurations.<host>.config.chrome.policy.file`).";
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = "${install}";

    launchd.daemons.chrome-policy.serviceConfig = {
      ProgramArguments = [ "${install}" ];
      RunAtLoad = true;
      # Both levels: ManagedClient recreates the per-user dir itself, which
      # only the parent's watch is guaranteed to see.
      WatchPaths = [
        "/Library/Managed Preferences"
        "/Library/Managed Preferences/${username}"
      ];
    };
  };
}
