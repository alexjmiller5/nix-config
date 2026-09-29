{ config, pkgs, ... }:

# Global git pre-commit hook: every staged change in every repo is scanned by
# ggshield - GitGuardian's own detectors, the ones behind its incident emails -
# before it can enter history. programs.git.hooks sets core.hooksPath, which
# replaces .git/hooks wholesale, so the script chains a repo's own hook instead
# of silently dropping it. The scan key is read from the AI Agent vault at
# commit time through the same auth seams as op-wrappers.nix; with no auth
# source at all the hook fails closed (`git commit --no-verify` is the escape
# hatch for an offline commit). Shared by both hosts.
let
  ggshield = pkgs.ggshield.overridePythonAttrs (old: {
    # Windows-only path test; it asserts on a mock call count and fails on darwin.
    disabledTests = (old.disabledTests or [ ]) ++ [ "test_git_command_includes_longpaths_on_windows" ];
  });
  preCommit = pkgs.writeShellApplication {
    name = "git-pre-commit";
    runtimeInputs = [
      config.opConnect.cliPackage
      config.programs.git.package
      ggshield
    ];
    text = ''
      ${builtins.readFile ./agent-detect.sh}
      ${builtins.readFile ./agent-op-env.sh}
      ${builtins.readFile ./git-pre-commit.sh}
    '';
  };
in
{
  imports = [ ./op-connect.nix ];
  programs.git.hooks.pre-commit = "${preCommit}/bin/git-pre-commit";
}
