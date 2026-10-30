{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.herdr-desktop;
  core = pkgs.callPackage ../pkgs/herdr-core.nix { };
  app = pkgs.callPackage ../pkgs/herdr-app.nix { };
  navigate = pkgs.writeShellApplication {
    name = "herdr-navigate";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../scripts/herdr-navigate.py} --herdr-app ${lib.getExe app} "$@"
    '';
  };
  native = pkgs.writeShellApplication {
    name = "herdr-native";
    runtimeInputs = [ core ];
    text = ''
      export HERDR_CORE_BIN=${lib.getExe core}
      ${lib.optionalString cfg.app.enable "export HERDR_APP_BIN=${lib.getExe app}"}
      exec ${pkgs.python3}/bin/python3 ${../scripts/herdr-native.py} "$@"
    '';
  };
  settingsFile = pkgs.writeText "herdr-desktop-settings.json" (builtins.toJSON cfg.settings);
in
{
  imports = [ ../modules/manual-steps.nix ];
  options.programs.herdr-desktop = {
    enable = lib.mkEnableOption "the Herdr desktop core";
    app.enable = lib.mkEnableOption "the native Herdr window";
    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      description = "Native settings merged at activation; other app preferences remain writable.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      core
      native
    ]
    ++ lib.optionals cfg.app.enable [
      app
      navigate
    ];
    launchd.agents.herdr-native-titles = lib.mkIf cfg.app.enable {
      enable = true;
      config = {
        Label = "org.nix-community.herdr-native-titles";
        ProgramArguments = [
          (lib.getExe native)
          "watch"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        EnvironmentVariables.PATH = "/usr/bin:/bin";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-native-titles.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-native-titles.log";
      };
    };
    home.activation.herdrNativeLegacyGuards =
      lib.hm.dag.entryAfter
        [
          "herdrClaudeIntegration"
          "piIntegrations"
        ]
        ''
          run ${lib.getExe native} guard-legacy
        '';
    manual.steps.native-herdr-remote = lib.mkIf cfg.app.enable {
      title = "Native Herdr remote enrollment";
      owner = "herdr";
      body = ''
        Enroll the remote machine through `hc machine add <ssh-host> --name <label>`
        using the user's existing supported SSH sign-in. The remote host needs the
        Nix-managed core; never use hc's imperative install/update option.
        Reenroll replacement machines through this interface. Native machine
        enrollment and session history are app state, not Nix or Git credentials.

        Option+H opens the app. Cmd+Shift+[/] traverses all open sessions across
        machines/spaces. Cmd+W saves exact conversation identities and split
        topology, then ends the processes; Cmd+Shift+T resumes the saved tab.
        Shell tabs reopen shells without replaying commands. Unsupported programs
        and agents without an exact identity stay open. Automatic names preserve
        manual labels. Cmd+Shift+W closes the viewer while programs keep running.
        Clicked close buttons use the app's native close; use Cmd+W for saved undo.
      '';
      verify = ''hc machine ls --json | jq -e 'any(.machines[]; .state == "connected")' >/dev/null'';
      redo = "after replacing the client or remote machine";
    };
    programs.zsh.envExtra = lib.mkBefore ''
      if [ -n "''${HC_TERMINAL_ID:-}" ]; then
        unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_TAB_ID
      fi
    '';
    # Keep native preferences writable: only declared keys are enforced on switch.
    home.activation.herdrDesktopSettings = lib.mkIf cfg.app.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings=${lib.escapeShellArg "${config.xdg.configHome}/herdr-app/settings.json"}
        run mkdir -p "$(dirname "$settings")"
        if [ -z "''${DRY_RUN_CMD:-}" ]; then
          previous="$settings"
          [ -f "$previous" ] || previous=/dev/null
          temporary=$(mktemp "$settings.XXXXXX")
          ${pkgs.jq}/bin/jq -s 'reduce .[] as $item ({}; . * $item)' "$previous" ${settingsFile} > "$temporary"
          mv "$temporary" "$settings"
        fi
      ''
    );
    xdg.configFile."herdr-app/themes/catppuccin-latte.json" = lib.mkIf cfg.app.enable {
      source = ../dotfiles/herdr-app/catppuccin-latte.json;
    };
    xdg.configFile."herdr-app/themes/catppuccin-mocha.json" = lib.mkIf cfg.app.enable {
      source = ../dotfiles/herdr-app/catppuccin-mocha.json;
    };
    xdg.configFile."herdr-app/keys.json" = lib.mkIf cfg.app.enable {
      source = ../dotfiles/herdr-app/keys.json;
    };
  };
}
