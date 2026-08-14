# macOS settings shared by all hosts

{ lib, ... }:

{
  # Skip building nix-darwin's own manual (options.json → man configuration.nix
  # + darwin-help HTML): it trips a "store path without context" warning on
  # every switch (upstream nix-darwin issue) and nobody reads it here — options
  # get looked up via search.nixos.org/mcp-nixos. mkForce keeps regular package
  # man pages: the documentation module hard-assigns programs.man.enable from
  # documentation.man.enable, which we're turning off.
  documentation.man.enable = false;
  documentation.doc.enable = false;
  programs.man.enable = lib.mkForce true;

  # home-manager's zsh already runs compinit (dump in ~/.config/zsh); the
  # system-level one in /etc/zshrc double-runs it and litters ~/.zcompdump.
  programs.zsh.enableCompletion = false;

  system.defaults = {
    NSGlobalDomain = {
      "com.apple.trackpad.scaling" = 5.0;
      InitialKeyRepeat = 10;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;
      AppleShowAllExtensions = true;
    };

    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.0;
      show-recents = false;
      minimize-to-application = true;
      mru-spaces = false;
      # Hot corners: all off (0 = no-op)
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
    };

    finder = {
      QuitMenuItem = true;
      AppleShowAllFiles = true;
      _FXShowPosixPathInTitle = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXSortFoldersFirst = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # list view
      FXDefaultSearchScope = "SCcf"; # search current folder
    };

    WindowManager = {
      EnableStandardClickToShowDesktop = false;
      EnableTiledWindowMargins = false;
    };

    CustomUserPreferences = {
      # no typed option for mouse speed (only trackpad)
      NSGlobalDomain."com.apple.mouse.scaling" = 5.0;
      "com.apple.finder" = {
        StandardViewSettings = {
          ExtendedListViewSettings_calculateAllSizes = true;
        };
        ListViewSettings = {
          calculateAllSizes = true;
        };
      };
      # iCloud Drive "Optimize Mac Storage" behavior
      "com.apple.bird" = {
        optimize-storage = true;
      };
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
      "com.google.Chrome".DisablePrintPreview = true;
      # Menu bar system-icon visibility lives in the ByHost controlcenter
      # domain on macOS 26 (the plain-domain "NSStatusItem Visible" keys are
      # ignored post-migration) → declared in home/macos/menu-bar.nix instead.
      "com.apple.menuextra.clock" = {
        IsAnalog = false;
        TimeAnnouncementsEnabled = false;
      };
    };
  };
}
