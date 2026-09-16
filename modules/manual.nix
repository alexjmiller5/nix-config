{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}:

# Renders this host's manual.steps (darwin + the user's Home Manager tree)
# into system.build.manual (MANUAL-<host>.md, committed via `just manual`)
# and installs `manual-check`, which runs each step's verify and prints
# done / todo / manual per step. Verify only: every step here is human by
# design (TCC, Keychain ACLs, pairings, admin password).
let
  render = import ./manual-render.nix { inherit lib; };
  hmSteps = config.home-manager.users.${username}.manual.steps;
  dup = lib.intersectLists (lib.attrNames config.manual.steps) (lib.attrNames hmSteps);
  steps =
    assert lib.assertMsg (
      dup == [ ]
    ) "manual.steps declared in both darwin and home-manager: ${toString dup}";
    config.manual.steps // hmSteps;
  host = config.manual.host;
  text = render {
    inherit host steps;
    rev = inputs.self.rev or inputs.self.dirtyRev or "unknown";
    docs = config.manual.docs;
    bootstrap = builtins.readFile (../docs/manual + "/${host}-bootstrap.md");
  };
  arg = lib.escapeShellArg;
  checkLines = lib.mapAttrsToList (
    _: s:
    if s.verify == null then
      "report manual ${arg s.owner} ${arg s.title}"
    else
      "check ${arg s.owner} ${arg s.title} ${arg s.verify}"
  ) steps;
  # Read-only captures of state nix cannot own (scripts/capture-snapshot);
  # snapshot steps diff the live capture against the committed snapshots/ file.
  captureSnapshot = pkgs.writeShellApplication {
    name = "capture-snapshot";
    runtimeInputs = [ pkgs.jq ];
    text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ../scripts/capture-snapshot);
  };
  manualCheck = pkgs.writeShellApplication {
    name = "manual-check";
    # Verify strings are single-quoted on purpose: bash -c expands them.
    excludeShellChecks = [ "SC2016" ];
    text = ''
      # Verifies this host's manual.steps; never performs one.
      todo=0
      report() { printf '%-6s %-20s %s\n' "$1" "$2" "$3"; }
      check() { # owner title verify-command
        if bash -c "$3" >/dev/null 2>&1; then report "done" "$1" "$2"
        elif [ $? -eq 3 ]; then report skip "$1" "$2" # cannot verify in this context
        else report todo "$1" "$2"; todo=1; fi
      }
      ${lib.concatStringsSep "\n" checkLines}
      exit "$todo"
    '';
  };
in
{
  imports = [ ./manual-steps.nix ];

  options.manual = {
    host = lib.mkOption {
      type = lib.types.str;
      description = "Host slug: names MANUAL-<host>.md and docs/manual/<host>-bootstrap.md.";
    };
    docs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Repo-relative docs linked under the manual's Reference section.";
    };
  };

  config = {
    home-manager.sharedModules = [ ./manual-steps.nix ];
    system.build.manual = pkgs.writeText "MANUAL-${host}.md" text;
    environment.systemPackages = [
      manualCheck
      captureSnapshot
    ];
  };
}
