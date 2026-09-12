{ config, lib, ... }:

let
  cfg = config.macos.finder;
  listView = {
    calculateAllSizes = lib.mkDefault true;
  }
  // lib.optionalAttrs cfg.desktop.enable {
    iconSize = lib.mkDefault 32;
  };
in
{
  options.macos.finder.desktop.enable = lib.mkEnableOption "desktop Finder preferences";

  config = {
    targets.darwin.defaults = {
      NSGlobalDomain.AppleShowAllExtensions = lib.mkDefault true;
      "com.apple.finder" = {
        QuitMenuItem = lib.mkDefault true;
        AppleShowAllFiles = lib.mkDefault true;
        _FXShowPosixPathInTitle = lib.mkDefault true;
        ShowPathbar = lib.mkDefault true;
        ShowStatusBar = lib.mkDefault true;
        _FXSortFoldersFirst = lib.mkDefault true;
        FXEnableExtensionChangeWarning = lib.mkDefault false;
        FXPreferredViewStyle = lib.mkDefault "Nlsv";
        FXDefaultSearchScope = lib.mkDefault "SCcf";

        # Finder uses V2 list settings on current macOS and the legacy
        # dictionary for other list contexts. These are nested dictionaries,
        # not flattened keys. Per-folder .DS_Store choices still take priority.
        StandardViewSettings = {
          ExtendedListViewSettingsV2 = listView;
          ListViewSettings = listView;
        };
      }
      // lib.optionalAttrs cfg.desktop.enable {
        _FXSortFoldersFirstOnDesktop = lib.mkDefault true;
        ShowHardDrivesOnDesktop = lib.mkDefault true;
        ShowExternalHardDrivesOnDesktop = lib.mkDefault true;
        ShowRemovableMediaOnDesktop = lib.mkDefault true;
        ShowMountedServersOnDesktop = lib.mkDefault false;
        NewWindowTarget = lib.mkDefault "PfDe";
        FinderSpawnTab = lib.mkDefault true;
        FXRemoveOldTrashItems = lib.mkDefault true;
        WarnOnEmptyTrash = lib.mkDefault true;
        FXEnableRemoveFromICloudDriveWarning = lib.mkDefault true;
        ShowRecentTags = lib.mkDefault false;
      };
    };

    # This shape cannot configure Finder's nested list defaults. Remove it
    # only when it contains the single misplaced flag; preserve other data.
    home.activation.finderListDefaults = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/osascript -l JavaScript <<'JXA'
      ObjC.import('Foundation');
      const prefs = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.finder');
      const value = ObjC.deepUnwrap(prefs.objectForKey('ListViewSettings'));
      if (value && Object.keys(value).length === 1 && value.calculateAllSizes === true) {
        prefs.removeObjectForKey('ListViewSettings');
        prefs.synchronize;
      }
      JXA
    '';
  };
}
