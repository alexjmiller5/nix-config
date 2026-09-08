# One shared "agent Chrome" per machine: a headed Google Chrome on its own
# data dir, listening for remote debugging on a fixed port, started at login
# and kept alive. Every browser-driving job on the machine attaches to this
# one endpoint and opens its own tab, and every login done in its window -
# by a job or by a human over Screen Sharing - is there for all later runs.
# A non-default data dir is what makes Chrome honor the port (136+ ignores
# it on the default profile) and what keeps the per-connection Allow sheet
# away. Per-site profiles are the alternative only when isolation between
# sites is actually wanted.
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
      description = ''
        Chrome Web Store extension ids force-installed through the
        ExtensionInstallForcelist policy (browser-wide: every Chrome profile
        on this machine, the agent one included). Chrome 137+ dropped
        --load-extension, so this is the declarative way to give the agent
        browser an extension - e.g. one holding the tabGroups permission,
        which CDP lacks (chrome-control's cdp-group.mjs borrows it).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    system.defaults.CustomUserPreferences."com.google.Chrome".ExtensionInstallForcelist =
      lib.mkIf (cfg.extensions != [ ]) (map (id: "${id};https://clients2.google.com/service/update2/crx") cfg.extensions);

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
