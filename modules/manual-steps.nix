{ lib, ... }:

# Human steps nix cannot perform (TCC grants, Keychain ACLs, sign-ins,
# pairings). Declare them next to the module that needs them; modules/manual.nix
# renders every host's steps into MANUAL-<host>.md and bakes the verifies into
# `manual-check`. Importable by nix-darwin and Home Manager modules alike, so
# an exported homeModule that declares steps imports this file itself.
let
  step = lib.types.submodule {
    options = {
      title = lib.mkOption { type = lib.types.str; };
      owner = lib.mkOption {
        type = lib.types.str;
        description = "Module, package or app the step belongs to; groups the manual.";
      };
      phase = lib.mkOption {
        type = lib.types.enum [
          "after-switch"
          "snapshot"
        ];
        default = "after-switch";
        description = "after-switch: do once the config is live. snapshot: state nix cannot own, so the listed values ARE the declaration.";
      };
      desktop = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Must run from the logged-in desktop or Screen Sharing.";
      };
      body = lib.mkOption { type = lib.types.lines; };
      verify = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Shell that exits 0 once the step is done; null = unverifiable by machine.";
      };
      redo = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "When the step must be repeated.";
      };
    };
  };
in
{
  options.manual.steps = lib.mkOption {
    type = lib.types.attrsOf step;
    default = { };
  };
}
