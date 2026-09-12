{
  config,
  lib,
  pkgs,
  ...
}:

# Explicit initial bootstrap only, shared by both hosts. Never register this
# helper in Git config or activation: a later switch must not read the machine
# vault even if a companion clone is missing. Routine sync uses git.nix's gh.
let
  cfg = config.machineVaultGit;
  helper =
    repo:
    "!${pkgs.writeShellScript "git-credential-bootstrap" ''
      set -eu
      [ "''${1:-}" = get ] || exit 0
      protocol= host= path=
      while IFS='=' read -r key value && [ -n "$key" ]; do
        case "$key" in
          protocol) protocol=$value ;;
          host) host=$value ;;
          path) path=$value ;;
        esac
      done
      [ "$protocol" = https ] && [ "$host" = github.com ] &&
        [ "$path" = ${lib.escapeShellArg "${repo}.git"} ] || exit 0
      unset OP_CONNECT_HOST OP_CONNECT_TOKEN
      OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${lib.escapeShellArg cfg.patAuthFile})"
      [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]
      export OP_SERVICE_ACCOUNT_TOKEN
      password="$(${pkgs._1password-cli}/bin/op read ${lib.escapeShellArg cfg.patOpRef})"
      [ -n "$password" ]
      printf 'username=x-access-token\npassword=%s\n' "$password"
    ''}";
in
{
  options.machineVaultGit = {
    patOpRef = lib.mkOption {
      type = lib.types.str;
      description = "op:// reference (IDs, not names) to this machine's fine-grained GitHub PAT in its machine vault.";
    };
    patAuthFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the machine SA token that can read patOpRef (the machine-sa agenix secret path).";
    };
    patRepos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "owner/name GitHub repos allowed to use the machine PAT during initial cloning only; must match its repo grants.";
    };
    companionRepos = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "owner/name -> clone destination; cloned if missing by the explicit bootstrap-companion-repos command.";
    };
  };

  config.home.packages = [
    (pkgs.writeShellApplication {
      name = "bootstrap-companion-repos";
      text = ''
        export GIT_TERMINAL_PROMPT=0
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (repo: dest: ''
            if [ ! -e ${lib.escapeShellArg "${dest}/.git"} ]; then
              if [ -e ${lib.escapeShellArg dest} ]; then
                echo ${lib.escapeShellArg "bootstrap-companion-repos: ${dest} exists without .git; preserve it elsewhere before initial cloning"} >&2
                exit 1
              fi
              ${pkgs.git}/bin/git ${lib.optionalString (lib.elem repo cfg.patRepos) ''
                -c credential.helper= -c credential.useHttpPath=true \
                -c ${lib.escapeShellArg "credential.helper=${helper repo}"} \
              ''}clone --quiet ${lib.escapeShellArg "https://github.com/${repo}.git"} ${lib.escapeShellArg dest}
            fi
          '') cfg.companionRepos
        )}
      '';
    })
  ];
}
