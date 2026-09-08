# One shared "agent Chrome" per machine: a headed Google Chrome on its own
# data dir, listening for remote debugging on a fixed port, started at login
# and kept alive. Every browser-driving job on the machine attaches to this
# one endpoint and opens its own tab, and every login done in its window -
# by a job or by a human over Screen Sharing - is there for all later runs.
# A non-default data dir is what makes Chrome honor the port (136+ ignores
# it on the default profile) and what keeps the per-connection Allow sheet
# away. Per-site profiles are the alternative only when isolation between
# sites is actually wanted.
#
# Extensions the agent browser needs (Claude in Chrome, whose tabGroups
# permission chrome-control's cdp-group.mjs borrows) come in through
# `extensions`: store ids force-installed by the machine's Chrome policy
# (modules/chrome-policy.nix, mandatory via Managed Preferences - a
# user-level ExtensionInstallForcelist is only Recommended and ignored).
# Signing into them is per profile and GUI-only (the host's MANUAL file).
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.agent-chrome;
in
{
  options.services.agent-chrome = {
    enable = lib.mkEnableOption "the shared remote-debuggable Chrome";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Login user whose GUI session hosts the browser.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/Users/${cfg.user}/.local/share/agent-chrome";
      defaultText = lib.literalExpression ''"~/.local/share/agent-chrome" (expanded for `user`)'';
      description = "Chrome data dir (the profile). Must not be Chrome's default one.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9222;
      description = "Remote-debugging port; jobs attach to 127.0.0.1:<port>.";
    };

    chromePath = lib.mkOption {
      type = lib.types.str;
      default = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
      description = "Chrome executable.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional Chrome command-line flags.";
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "fcoeoabgfenejglbffodgkkbkcdhcgfn" ];
      description = "Chrome Web Store extension ids force-installed (and toolbar-pinned) through the machine's Chrome policy - browser-wide, so every profile on the machine gets them.";
    };
  };

  config = lib.mkIf cfg.enable {
    chrome.policy = lib.mkIf (cfg.extensions != [ ]) {
      enable = true;
      settings.ExtensionSettings = lib.genAttrs cfg.extensions (_: {
        installation_mode = "normal_installed";
        update_url = "https://clients2.google.com/service/update2/crx";
        toolbar_pin = "force_pinned";
      });
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      /bin/mkdir -p ${lib.escapeShellArg cfg.dataDir}
      /usr/sbin/chown ${lib.escapeShellArg cfg.user} ${lib.escapeShellArg cfg.dataDir}
    '';

    launchd.user.agents.agent-chrome = {
      serviceConfig = {
        Label = "com.alexmiller.agent-chrome";
        ProgramArguments = [
          cfg.chromePath
          "--user-data-dir=${cfg.dataDir}"
          "--remote-debugging-port=${toString cfg.port}"
          "--no-first-run"
          "--no-default-browser-check"
          "--restore-last-session"
        ]
        ++ cfg.extraArgs;
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Interactive"; # a real window, for Screen Sharing logins
        StandardOutPath = "/Users/${cfg.user}/Library/Logs/agent-chrome.log";
        StandardErrorPath = "/Users/${cfg.user}/Library/Logs/agent-chrome.log";
      };
    };
  };
}
