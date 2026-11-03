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
  layoutExamples = pkgs.fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr-layout-examples";
    rev = "0ec967640bf854ffb839e9af06c1e0c328bc9815";
    sha256 = "0ckp5vkv8d0zliyhqxg51350ad2fj8q7yqg1mhcm889b8l33ic5y";
  };
  exampleMods = {
    pasture = [ "pasture" ];
    threads = [
      "t4-composer"
      "t4-details"
      "t4-diff"
      "t4-files"
      "t4-head"
      "t4-new"
      "t4-panel-head"
      "t4-threads"
    ];
  };
  exampleFiles = lib.listToAttrs (
    map (name: {
      name = "herdr-app/layouts/${name}.json";
      value.source = "${layoutExamples}/${name}/layouts/${name}.json";
    }) cfg.exampleLayouts
  );
  layoutMods =
    lib.foldl'
      (
        mods: name: mods // lib.genAttrs exampleMods.${name} (mod: "${layoutExamples}/${name}/mods/${mod}")
      )
      (lib.optionalAttrs cfg.agentSidebar.enable {
        agent-sidebar = ../dotfiles/herdr-app/agent-sidebar;
        compact-terminals-bar = ../dotfiles/herdr-app/compact-terminals-bar;
      })
      cfg.exampleLayouts;
  settingsFile = pkgs.writeText "herdr-desktop-settings.json" (builtins.toJSON cfg.settings);
in
{
  imports = [ ../modules/manual-steps.nix ];
  options.programs.herdr-desktop = {
    enable = lib.mkEnableOption "the Herdr desktop core";
    app.enable = lib.mkEnableOption "the native Herdr window";
    agentSidebar.localLabel = lib.mkOption {
      type = lib.types.str;
      default = "Local";
      description = "Display name for the computer running the Herdr window.";
    };
    agentSidebar.enable = lib.mkEnableOption "the Terminals layout with a minimal machine-grouped agent sidebar";
    exampleLayouts = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (builtins.attrNames exampleMods));
      default = [ ];
      description = "Pinned official Herdr example layouts and their required mods.";
    };
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
        Shell tabs reopen shells without replaying commands. Codex/Claude tabs
        without a saved identity reopen in their resume picker. Unsupported
        programs stay open. Automatic names preserve
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
    # Herdr's asset sandbox refuses symlinks that escape its config directory.
    home.activation.herdrLayoutMods = lib.mkIf cfg.app.enable (
      lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: source: ''
            target=${lib.escapeShellArg "${config.xdg.configHome}/herdr-app/mods/${name}"}
            if [ -L "$target" ]; then
              run unlink "$target"
            fi
            run mkdir -p "$target"
            run ${pkgs.rsync}/bin/rsync -r --chmod=Du+w,Fu+w --delete \
              --exclude=gpui-kit.d.ts --exclude=herdr.d.ts --exclude=jsconfig.json \
              ${lib.escapeShellArg "${source}/"} "$target/"
          '') layoutMods
        )
      )
    );
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
    xdg.configFile = lib.mkIf cfg.app.enable (
      exampleFiles
      // lib.optionalAttrs cfg.agentSidebar.enable {
        "herdr-app/layouts/terminals-agents.json".text =
          builtins.replaceStrings [ ''"@localLabel@"'' ] [ (builtins.toJSON cfg.agentSidebar.localLabel) ]
            (builtins.readFile ../dotfiles/herdr-app/terminals-agents.json);
      }
      // {
        "herdr-app/themes/catppuccin-latte.json" = {
          source = ../dotfiles/herdr-app/catppuccin-latte.json;
        };
        "herdr-app/themes/catppuccin-mocha.json" = {
          source = ../dotfiles/herdr-app/catppuccin-mocha.json;
        };
        "herdr-app/keys.json" = {
          source = ../dotfiles/herdr-app/keys.json;
        };
      }
    );
  };
}
