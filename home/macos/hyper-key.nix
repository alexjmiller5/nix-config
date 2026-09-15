{ config, lib, ... }:
let
  cfg = config.macos.hyperKey;
  ids = lib.splitString "-" cfg.keyboardKey;
  args = [
    "/usr/bin/hidutil"
    "property"
    "--matching"
    (builtins.toJSON {
      VendorID = builtins.fromJSON (builtins.elemAt ids 0);
      ProductID = builtins.fromJSON (builtins.elemAt ids 1);
      PrimaryUsagePage = 1;
      PrimaryUsage = 6;
    })
    "--set"
    (builtins.toJSON {
      UserKeyMapping = [
        {
          HIDKeyboardModifierMappingSrc = 30064771129;
          HIDKeyboardModifierMappingDst = 30064771182;
        }
      ];
    })
  ];
in
{
  options.macos.hyperKey = {
    enable = lib.mkEnableOption "Caps Lock as F19 for Hammerspoon Hyper";
    keyboardKey = lib.mkOption {
      type = lib.types.strMatching "(0|[1-9][0-9]*)-(0|[1-9][0-9]*)-[01]";
      default = "0-0-0";
      description = ''
        Native modifier preference key suffix: VendorID-ProductID-HIDVirtualDevice.
        The immediate and login remaps match keyboards with these vendor/product IDs
        (0 matches every keyboard).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."hammerspoon/native-hyper".text = "f19\n";

    # Apple HID usages: keyboard page 0x07, Caps Lock 0x39, F19 0x6e. A plain
    # key carries no modifier, so Hyper chords never collide with system or app
    # shortcuts. Native modifier preferences cannot target F19, so the mapping
    # is hidutil only; drop the global Caps-to-modifier preference an earlier
    # version of this module wrote (System Settings uses per-keyboard keys).
    home.activation.nativeHyperKey = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/defaults -currentHost delete -g ${lib.escapeShellArg "com.apple.keyboard.modifiermapping.${cfg.keyboardKey}"} 2>/dev/null || true
      run ${lib.escapeShellArgs args}
    '';

    # hidutil is transient; reapply once at login without a resident remapping app.
    launchd.agents.native-hyper-key = {
      enable = true;
      config = {
        Label = "org.nix-community.home.native-hyper-key";
        ProgramArguments = args;
        RunAtLoad = true;
      };
    };
  };
}
