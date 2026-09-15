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
  imports = [ ../../modules/manual-steps.nix ];

  options.macos.finder.desktop.enable = lib.mkEnableOption "desktop Finder preferences";

  config = {

    # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
    manual.steps = lib.mkIf cfg.desktop.enable {
      finder-sidebar = {
        title = "Finder sidebar selections";
        owner = "finder";
        phase = "snapshot";
        desktop = true;
        body = ''
          Set the remaining Sidebar selections in Finder Settings on a replacement Mac:

          - Favorites: Applications, Desktop, Documents, and Downloads enabled.
          - Locations: External disks and CDs/DVDs/iOS Devices enabled.
          - Disable the other pictured entries: Recents, Shared, Movies, Music,
            Pictures, iCloud Drive, Cloud Storage, home folder, On My Mac, the computer,
            Hard disks, AirDrop, Bonjour computers, Connected servers, and Trash.

          Modern Finder stores these selections in shared-file-list archives containing
          machine-bound bookmarks. The available CLI and supported management APIs do
          not expose the complete checkbox set; do not copy those archives or write
          the obsolete `com.apple.sidebarlists` domain.
        '';
      };
    };

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
