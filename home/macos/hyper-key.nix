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
  imports = [ ../../modules/manual-steps.nix ];

  imports = [ ../../modules/manual-steps.nix ];

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

    # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
    manual.steps = {
      hyper-key-test = {
        title = "Test the Hyper key after enrolling";
        owner = "hyper-key";
        desktop = true;
        body = ''
          Hold Caps with a shortcut key for Hyper. A quick unused tap toggles Caps Lock.
          Right Control is reserved for Hyper on enabled Hammerspoon profiles. Secure
          Input prevents interception: Caps is only Right Control in that context, and
          Hyper is unavailable before login. After enrolling another Mac, test Caps+B,
          release Caps and type normally, then repeat after a fresh login.
        '';
      };
    };

    xdg.configFile."hammerspoon/native-hyper".text = "f19\n";

    # Apple HID usages: keyboard page 0x07, Caps Lock 0x39, F19 0x6e. A plain
    # key carries no modifier, so Hyper chords never collide with system or app
    # shortcuts. Native modifier preferences cannot target F19, so the mapping
    # is hidutil only. The native modifier remap runs before hidutil's key map
    # and would swallow Caps first, so this keyboard's modifier preference is
    # pinned to the identity pair System Settings itself writes for "no
    # change". A stale Caps remap stays cached until the next login; only
    # login rebuilds it. (The built-in keyboard reports vendor 0, product 0.)
    home.activation.nativeHyperKey = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/defaults -currentHost write -g ${lib.escapeShellArg "com.apple.keyboard.modifiermapping.${cfg.keyboardKey}"} -array \
        '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771129</integer></dict>'
      run ${lib.escapeShellArgs args}
    '';

    # macOS caches the native modifier remap until the next login, so the first
    # activation (and any change to what Caps Lock maps to) needs a logout.
    manual.steps.hyper-key-relogin = {
      title = "Log out after the first Hyper key activation";
      owner = "hyper-key";
      phase = "after-switch";
      body = ''
        macOS applies the native modifier remap (System Settings > Modifier Keys,
        `com.apple.keyboard.modifiermapping.<vid>-<pid>-0`; the built-in keyboard
        is `0-0-0`) before hidutil's key map and caches it until the next login.
        After this module first activates, or whenever the Caps Lock target
        changes, log out and back in (or restart): until then `hidutil --get`
        shows the new map while Caps still arrives as the old key.
      '';
      redo = "after any change to the Caps Lock mapping";
    };

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
