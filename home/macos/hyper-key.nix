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
          HIDKeyboardModifierMappingDst = 30064771300;
        }
      ];
    })
  ];
in
{
  options.macos.hyperKey = {
    enable = lib.mkEnableOption "native Caps Lock to right Control for Hammerspoon Hyper";
    keyboardKey = lib.mkOption {
      type = lib.types.strMatching "(0|[1-9][0-9]*)-(0|[1-9][0-9]*)-[01]";
      default = "0-0-0";
      description = ''
        Native modifier preference key suffix: VendorID-ProductID-HIDVirtualDevice.
        The immediate and login remaps match keyboards with these vendor/product IDs.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."hammerspoon/native-hyper".text = "rightctrl\n";

    # Apple HID usages: keyboard page 0x07, Caps Lock 0x39, right Control 0xe4.
    # Preserve independent modifier choices in the native per-keyboard preference.
    home.activation.nativeHyperKey = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/osascript -l JavaScript <<'JXA'
      ObjC.import('Foundation');
      const app = Application.currentApplication();
      app.includeStandardAdditions = true;
      const domain = '-g';
      const key = ${builtins.toJSON "com.apple.keyboard.modifiermapping.${cfg.keyboardKey}"};
      const quote = value => "'" + value.replace(/'/g, "'\"'\"'") + "'";
      const defaults = '/usr/bin/defaults -currentHost ';
      let pairs = [];
      let nativePairs;
      let stored;
      try { stored = app.doShellScript(defaults + 'export ' + quote(domain) + ' -'); }
      catch (error) { if (!error.message.includes('does not exist')) throw error; }
      if (stored !== undefined) {
        const data = $(stored).dataUsingEncoding($.NSUTF8StringEncoding);
        const nativePrefs = $.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 0, null, null);
        const prefs = ObjC.deepUnwrap(nativePrefs);
        if (!prefs || typeof prefs !== 'object' || Array.isArray(prefs)) throw Error('Could not read native keyboard preferences');
        nativePairs = nativePrefs.objectForKey(key);
        pairs = prefs[key] === undefined ? [] : prefs[key];
      }
      if (!Array.isArray(pairs)) throw Error('Native keyboard modifier preference must be an array');
      const updated = $.NSMutableArray.alloc.init;
      pairs.forEach((pair, index) => {
        if (!pair || pair.HIDKeyboardModifierMappingSrc !== 30064771129) updated.addObject(nativePairs.objectAtIndex(index));
      });
      const replacement = $.NSMutableDictionary.alloc.init;
      replacement.setObjectForKey($.NSNumber.numberWithLongLong(30064771129), 'HIDKeyboardModifierMappingSrc');
      replacement.setObjectForKey($.NSNumber.numberWithLongLong(30064771300), 'HIDKeyboardModifierMappingDst');
      updated.addObject(replacement);
      const data = $.NSPropertyListSerialization.dataWithPropertyListFormatOptionsError(updated, $.NSPropertyListXMLFormat_v1_0, 0, null);
      const xml = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
      app.doShellScript(defaults + 'write ' + quote(domain) + ' ' + quote(key) + ' ' + quote(xml));
      JXA
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
