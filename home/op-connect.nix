# Official local Connect containers, plus a memory-only token handoff. Import
# on any host; enable where Docker Desktop and independently enrolled operator
# credentials are available.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.opConnect;
  json = pkgs.formats.json { };
  credentials = "${cfg.stateDirectory}/1password-credentials.json";
  container = image: {
    image = "1password/connect-${image}:${cfg.version}";
    restart = "unless-stopped";
    volumes = [
      {
        type = "bind";
        source = credentials;
        target = "/home/opuser/.op/1password-credentials.json";
        read_only = true;
        bind.create_host_path = false;
      }
      "data:/home/opuser/.op/data"
    ];
    environment.OP_LOG_LEVEL = "warn";
    security_opt = [ "no-new-privileges:true" ];
    cap_drop = [ "ALL" ];
  };
  compose = json.generate "op-connect-compose.json" {
    name = cfg.projectName;
    services = {
      api = container "api" // {
        ports = [ "127.0.0.1:${toString cfg.port}:8080" ];
      };
      sync = container "sync";
    };
    volumes.data = { };
  };
  settings = json.generate "op-connect-config.json" {
    inherit (cfg)
      vaultId
      stateDirectory
      serviceAccountTokenFile
      credentialsItemId
      tokenOpRef
      dockerApp
      docker
      ;
    host = "http://127.0.0.1:${toString cfg.port}";
    op = "${pkgs._1password-cli}/bin/op";
    composeFile = compose;
  };
  runner = "${pkgs.python3}/bin/python3 ${../scripts/op-connect.py} ${settings}";
  op = pkgs.writeShellScriptBin "op" ''
    ${builtins.readFile ./agent-detect.sh}
    ${builtins.readFile ./agent-op-env.sh}
    exec ${runner} exec "$@"
  '';
in
{
  options.opConnect = {
    enable = lib.mkEnableOption "local 1Password Connect for agent-vault reads";
    vaultId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The one vault this local Connect server and read token can access.";
    };
    credentialsItemId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Document item ID holding the original encrypted credentials bundle.";
    };
    tokenOpRef = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "ID-based secret reference for the Connect read token.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/1password-connect";
      description = "Private directory for the encrypted credentials bundle and Unix socket.";
    };
    serviceAccountTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/state/op/agent-sa-token";
      description = "Existing agent SA token used for bootstrap and direct operations.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Connect API port, bound only to IPv4 loopback.";
    };
    version = lib.mkOption {
      type = lib.types.str;
      default = "1.8.1";
      description = "Pinned official Connect API and sync image version.";
    };
    projectName = lib.mkOption {
      type = lib.types.str;
      default = "op-connect";
      description = "Docker Compose project that owns the containers and encrypted cache volume.";
    };
    dockerApp = lib.mkOption {
      type = lib.types.str;
      default = "/Applications/Docker.app";
      description = "Docker Desktop application to open at login.";
    };
    docker = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dockerApp}/Contents/Resources/bin/docker";
      description = "Docker CLI path.";
    };
    cliPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = if cfg.enable then op else pkgs._1password-cli;
      description = "op CLI with selective Connect routing when enabled.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vaultId != "" && cfg.credentialsItemId != "" && cfg.tokenOpRef != "";
        message = "opConnect requires vaultId, credentialsItemId and tokenOpRef from provisioning.";
      }
    ];
    xdg.configFile."1password-connect/compose.json".source = compose;
    home.packages = [
      cfg.cliPackage
      (pkgs.writeShellScriptBin "op-connect-start" ''
        exec /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/org.nix-community.op-connect"
      '')
      (pkgs.writeShellScriptBin "op-connect-bootstrap" ''
        exec ${pkgs.python3}/bin/python3 ${../scripts/op-connect-bootstrap.py} "$@"
      '')
    ];
    launchd.agents.op-connect = {
      enable = true;
      config = {
        Label = "org.nix-community.op-connect";
        ProgramArguments = [
          "${pkgs.python3}/bin/python3"
          "${../scripts/op-connect.py}"
          "${settings}"
          "serve"
        ];
        EnvironmentVariables = {
          PATH = "${cfg.dockerApp}/Contents/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          DOCKER_HOST = "unix://${config.home.homeDirectory}/.docker/run/docker.sock";
        };
        RunAtLoad = true;
        # No automatic auth retries after a quota failure. Containers restart
        # with Docker; this process holds the token until logout or restart.
        KeepAlive = false;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/op-connect.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/op-connect.log";
      };
    };
  };
}
