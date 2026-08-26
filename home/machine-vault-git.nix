{ config, lib, pkgs, ... }:

# Machine-vault git bootstrap, shared by both hosts (options set per host).
# Two pieces that exist for the same reason — a fresh machine must be able
# to clone its private companion repos before any login/agent state exists:
#
#  - a git credential helper serving this machine's fine-grained GitHub PAT
#    (read from the machine vault via the agenix-decrypted machine SA, IDs
#    not names) for EXACTLY the repos in patRepos. Everything else on
#    github.com falls through to git.nix's gh-wrapper default (AI Agent
#    vault) — agent credentials never ride machine-vault credentials.
#  - clone-if-missing activation for the companion working clones, which
#    makes the MANUAL clone steps self-healing: private clones warn and skip
#    on failure (re-run switch once the machine-sa secret decrypts).
#
# useHttpPath makes git consult the repo-scoped helper keys; the .git
# suffix is appended because path matching is exact and remotes carry it.
let
  cfg = config.machineVaultGit;
  helper = "!${pkgs.writeShellScript "git-credential-machine-vault" ''
    [ "$1" = get ] || exit 0
    printf 'username=alexjmiller5\n'
    printf 'password=%s\n' "$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${cfg.patAuthFile})" ${pkgs._1password-cli}/bin/op read '${cfg.patOpRef}')"
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
      description = "owner/name GitHub repos served by the machine-vault PAT helper — must match the PAT's repo grants.";
    };
    companionRepos = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "owner/name -> clone destination; cloned if missing at activation.";
    };
  };

  config = {
    programs.git.settings.credential =
      { "https://github.com".useHttpPath = true; }
      // lib.listToAttrs (map
        (repo: lib.nameValuePair "https://github.com/${repo}.git" { inherit helper; })
        cfg.patRepos);

    home.activation.companionRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      companionClone() {
        [ -d "$2" ] || /usr/bin/git clone --quiet "https://github.com/$1.git" "$2" \
          || echo "companion-repos: clone of $1 failed — machine-sa decrypted? PAT scoped to it? re-run switch" >&2
      }
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList
        (repo: dest: ''companionClone ${repo} "${dest}"'') cfg.companionRepos)}
    '';
  };
}
