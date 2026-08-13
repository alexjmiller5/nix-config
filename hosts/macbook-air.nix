{ pkgs, lib, username, ... }:

# MacBook Air — LIVE since 2026-07-28 (generation 1). Mirrors the mini minus
# its headless-server bits (never-sleep power settings, headless tailscaled)
# and its data-collection services (screentime/callhistory/finance-sync — the
# flake imports those modules for every host, but only mac-mini.nix enables
# them). Home profile: home/macbook-air.nix.
{
  imports = [ ../modules/notunes.nix ];

  system.stateVersion = 6;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # 1password-cli: op, used by the git credential helper. terraform: BSL,
  # kept for the OCI VM fleet (infra skill says Terraform is fine there).
  # vscode-extension- prefix: the licensed/platform-specific extensions that
  # come from pkgs.vscode-extensions in home/vscode.nix.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "1password-cli" "terraform" ]
    || lib.hasPrefix "vscode-extension-" (lib.getName pkg);

  # The laptop's ONE agenix secret: the macbook-air-machine 1P service-account
  # token (read-only on the "MacBook Air" vault). Every other secret lives in
  # that vault, fetched at runtime via op read — see secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-laptop.age;
    owner = username;
  };

  # The laptop's nix came from the standalone installer, which manages the
  # daemon itself; nix-darwin must not.
  nix.enable = false;

  # The laptop has a normal pre-existing /opt/homebrew; let nix-homebrew
  # adopt it on first activation instead of erroring.
  nix-homebrew.autoMigrate = true;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  environment.systemPackages = with pkgs; [
    git
    just
  ];

  # Canonical flake location: darwin-rebuild finds /etc/nix-darwin/flake.nix on
  # its own, so rebuild commands never need to know where the working clone
  # lives. A string (not a path literal) keeps the symlink out-of-store.
  environment.etc."nix-darwin".source = "/Users/${username}/.config/nix-config";

  # Tailscale runs via the GUI app (tailscale-app cask below), unlike the
  # mini's headless tailscaled.

  # yabai, fully declared: the org.nixos.yabai launchd agent runs the nix
  # package bare (so it loads ~/.yabairc from home/macbook-air.nix), the
  # yabai-sa daemon loads the scripting addition at boot, and the module
  # generates /etc/sudoers.d/yabai against the store binary's sha256 — the
  # hash and path move in lockstep on upgrades, no manual regen. Still
  # manual: the SIP partial-disable and re-granting Accessibility when the
  # store path changes (MANUAL-macbook-air.md).
  services.yabai = {
    enable = true;
    enableScriptingAddition = true;
  };

  # Disable auto display brightness (laptop-only; written to /Library/Preferences
  # as root — takes effect after a restart).
  system.defaults.CustomSystemPreferences = {
    "/Library/Preferences/com.apple.iokit.AmbientLightSensor" = {
      "Automatic Display Enabled" = false;
    };
  };

  # Chrome policy, declared. macOS Chrome reads enterprise policy ONLY from
  # /Library/Managed Preferences (root-owned) — policy keys in the normal user
  # defaults domain are silently ignored, so this is written by a root
  # activation script, not system.defaults. Laptop-only: the mini's Chrome
  # (finance scrapers) must stay bare. Chrome reloads policy on restart
  # (chrome://policy → Reload policies to force it).
  #
  # ExtensionSettings with installation_mode "normal_installed": auto-installs
  # from the Web Store, blocks UI uninstall, auto-updates — but the
  # enable/disable toggle stays Alex's, and a disable sticks. Flip an entry to
  # `force = true` (force_installed) to also force-enable it. Unlisted
  # extensions keep default behavior, so manual/dev-mode installs still work;
  # removing an entry returns that extension to manual control (it is NOT
  # auto-uninstalled).
  system.activationScripts.postActivation.text =
    let
      webstore = "https://clients2.google.com/service/update2/crx";
      normal = { installation_mode = "normal_installed"; update_url = webstore; };
      chromePolicy = pkgs.writeText "com.google.Chrome.policy.plist" (lib.generators.toPlist { escape = true; } {
        ExtensionSettings = {
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = normal; # 1Password – Password Manager
          "gighmmpiobklfepjocnamgkkbiglidom" = normal; # AdBlock
          "efaidnbmnnnibpcajpcglclefindmkaj" = normal; # Adobe Acrobat
          "kfaknphcidikmjhmmfmphghhlcoknflj" = normal; # Amazon Unsponsor
          "kagpmnfgpdecdkbhongbgkgppnpimime" = normal; # Bookmarks Exporter
          "iiikidmnimlpahbeknmkeonmemajpccj" = normal; # Button Stealer
          "cbhilkcodigmigfbnphipnnmamjfkipp" = normal; # Calendly
          "nenlahapcbofgnanklpelkaejcehkggg" = normal; # Capital One Shopping
          "ejcfepkfckglbgocfkanmcdngdijcgld" = normal; # ChatGPT search
          "fcoeoabgfenejglbffodgkkbkcdhcgfn" = normal; # Claude
          "fcalilbnpkfikdppppppchmkdipibalb" = normal; # Cloaq
          "ifjhcahbhkfojdmkndpkmkffbjnefido" = normal; # Cookie Guard
          "jlmpjdjjbgclbocgajdjefcidcncaied" = normal; # daily.dev | Where developers discover what's next
          "eimadpbcbfnmbkopoojfekhnkhdbieeh" = normal; # Dark Reader
          "gdkfehnloabjkmccddnjckpnlhcdcalh" = normal; # De-Sponsor for Amazon
          "cnpgabmfnfehdamobkafalnpdoigdlil" = normal; # FaviGrab
          "hnmpcagpplmpfojmgmnngilcnanddlhb" = normal; # Free VPN For Chrome
          "kfgepjmmgamniaefbjlbacahkjjnjoaa" = normal; # Gmail reverse conversation
          "jgjaapljoafhkohbnfigoekjgdfddnnn" = normal; # Gmail Show Time
          "mgijmajocgfcbeboacabfgobmjgjcoja" = normal; # Google Dictionary (by Google)
          "ghbmnnjooekpmoecnnnilnnbdlolhkhi" = normal; # Google Docs Offline
          "aapbdbdomjkkjkaonfhkkikfgjllcleb" = normal; # Google Translate
          "gjbnlmbnepomgkknbhclokdameangdan" = normal; # Insta Content Blocker
          "bcjindcccaagfpapjjmafapmmgkkhgoa" = normal; # JSON Formatter
          "chklaanhfefbnpoihckbnefhakgolnmc" = normal; # JSONVue
          "dijpdmknlincdehpemajfobhfcmjkhof" = normal; # LinkedIn Feed Blocker
          "iepgempfdndmbciedjdladndpoeodepl" = normal; # Lovable Project Downloader
          "nkbihfbeogaeaoehlefnkodbefgpgknn" = normal; # MetaMask
          "pobhoodpcipjmedfenaigbeloiidbflp" = normal; # Minimal Theme for Twitter / X
          "knheggckgoiihginacbkhaalnibhilkk" = normal; # Notion Web Clipper
          "bkhaagjahfmjljalopjnoealnfndnagc" = normal; # Octotree
          "jlgojbammkhdbbohlihccohgbaccgpbm" = normal; # Open Links in Tabs
          "chhjbpecpncaggjpdakmflnfcopglcmi" = normal; # Rakuten
          "fgacdjnoljjfikkadhogeofgjoglooma" = normal; # Raycast Companion
          "fmkadmapgofadopljbjfkapdkoienihi" = normal; # React Developer Tools
          "mmnhjecbajmgkapcinkhdnjabclcnfpg" = normal; # Reddit Promoted Ad Blocker
          "hlepfoohegkhhmjieoechaddaejaokhf" = normal; # Refined GitHub
          "gebbhagfogifgggkldgodflihgfeippi" = normal; # Return YouTube Dislike
          "bnhjfbjmbgmgllkojikabliaidpihfnp" = normal; # Reverbify
          "mpdajninpobndbfcldcmbpnnbhibjmch" = normal; # SAML-tracer
          "gmbmikajjgmnabiglmofipeabaddhgne" = normal; # Save to Google Drive
          "pbanhockgagggenencehbnadejlgchfc" = normal; # Simplify Copilot
          "mnjggcdmjocbbbhaepdhchncahnbgone" = normal; # SponsorBlock for YouTube
          "bgehnoihoklmofgehcefiaicdcdgppck" = normal; # Spotify Playback Speed
          "jcgpgjhaendighananonflfmjjefjjlp" = normal; # Streak Email Tracking for Gmail
          "pdmhehfogekmpmdoemhabjpaiadagpgp" = normal; # Student Beans
          "micdllihgoppmejpecmkilggmaagfdmb" = normal; # Tab Copy
          "dhdgffkkebhmkfjojejmpbldmpobfkfo" = normal; # Tampermonkey
          "ddkjiahejlhfcafbddmgiahcphecmpfh" = normal; # uBlock Origin Lite
          "pmbneaajfhcoecedlmkfkdnjemmebbcb" = normal; # UnSponsored
          "djflhoibgkdhkhhcedjiklpkjnoahfmg" = normal; # User-Agent Switcher for Chrome
          "dbepggeogbaibhgnhhndojpepiihcmeb" = normal; # Vimium
          "bfbameneiokkgbdmiekhjnmfkcnldhhm" = normal; # Web Developer
          "ppaojnbmmaigjmlpjaldnkgnklhicppk" = normal; # Webtime Tracker
          "jabopobgcpjmedljpbcaablpmlmfcogm" = normal; # WhatFont
          "jiaopdjbehhjgokpphdfgmapkobbnmjp" = normal; # Youtube-shorts block
        };

        # PWAs, force-installed per profile at Chrome launch; the
        # ~/Applications/Chrome Apps.localized/<Name>.app shims (dock
        # references Google Maps.app) are created on install and can't be
        # uninstalled in the UI while listed here. custom_name permanently
        # overrides the site manifest's name — it IS the shim's .app name,
        # so a fresh machine reproduces these exact names (and the dock's
        # Google Maps.app path keeps resolving).
        WebAppInstallForceList =
          let
            app = url: custom_name: {
              inherit url custom_name;
              default_launch_container = "window";
            };
          in [
            (app "https://secure.bankofamerica.com/myaccounts/signin/signIn.go" "BofA")
            (app "https://contacts.google.com/" "Google Contacts")
            (app "https://www.google.com/maps" "Google Maps")
            (app "https://translate.google.com/" "Google Translate")
            (app "https://web.groupme.com/" "GroupMe")
            (app "https://www.instagram.com/" "Instagram")
            (app "https://www.linkedin.com/feed/" "LinkedIn")
            (app "https://settleup.app/" "Settle Up")
            (app "https://www.snapchat.com/web" "Snapchat")
            (app "https://login.tailscale.com/admin" "Tailscale Admin Dashboard")
            (app "https://account.venmo.com/" "Venmo")
            (app "https://www.wordreference.com/enes/" "WordReference")
            (app "https://x.com/" "X")
            (app "https://www.youtube.com" "YouTube")
          ];
      });
    in
    ''
      mkdir -p '/Library/Managed Preferences/${username}'
      cp -f ${chromePolicy} '/Library/Managed Preferences/${username}/com.google.Chrome.plist'
      chmod 644 '/Library/Managed Preferences/${username}/com.google.Chrome.plist'
      /usr/bin/killall cfprefsd 2>/dev/null || true
    '';

  # Dock contents, in order (snapshotted 2026-08-02). The list IS the dock:
  # nix rewrites it on switch, so manual drag-ins don't survive.
  system.defaults.dock.persistent-apps = [
    { app = "/Applications/Spotify.app"; }
    { app = "/System/Applications/Messages.app"; }
    { app = "/Applications/WhatsApp.app"; }
    { app = "/System/Applications/Mail.app"; }
    { app = "/Applications/Ghostty.app"; }
    { app = "/Applications/Visual Studio Code.app"; }
    { app = "/Applications/Google Chrome.app"; }
    { app = "/Applications/Notion Calendar.app"; }
    { app = "/Applications/Notion.app"; }
    { app = "/Applications/Gemini.app"; }
    { app = "/Applications/Claude.app"; }
    { app = "/Users/alexmiller/Applications/Chrome Apps.localized/Google Maps.app"; }
  ];

  # Brew-ONLY leftovers — everything available in nixpkgs migrated to
  # home/macbook-air.nix home.packages on 2026-08-10 (dep cruft and the
  # unused ruby managers dropped outright; brew auto-keeps real deps).
  homebrew = {
    enable = true;
    taps = [
      # Alex's personal cask tap — apps released by their repos' CI
      # (gemini-desktop, receptor, ...).
      "alexjmiller5/tap"
      "smudge/smudge"
      "steipete/tap"
    ];
    brews = [
      "chrome-cli"
      "skills"
      "smudge/smudge/nightlight"
    ];
    casks = [
      "1password"
      # TODO: try moving to pkgs._1password-cli someday (already in the closure
      # via the gh/gcloud wrappers) — verify desktop-app integration (Touch ID
      # in Alex's terminals) still accepts the nix-built op before zapping this.
      "1password-cli"
      "alt-tab"
      "betterdisplay"
      "binary-ninja-free"
      "burp-suite"
      "claude"
      "claude-code"
      "codexbar"
      "discord"
      "docker-desktop"
      "dolphin"
      # From alexjmiller5/tap — released + notarized by gemini-desktop's CI.
      # Replaces the old imperative install.sh install. MUST stay fully
      # qualified: bare "gemini" is MacPaw's disk cleaner in homebrew/cask.
      "alexjmiller5/tap/gemini"
      "ghostty"
      "google-chrome"
      "hammerspoon"
      "karabiner-elements"
      "libreoffice"
      "mactex-no-gui"
      "notion"
      "notion-calendar"
      "notion-cli"
      # notunes comes from modules/notunes.nix
      "processing"
      "raycast"
      # From alexjmiller5/tap — released + notarized by receptor's CI.
      # Replaces the DerivedData rm-cp-codesign flow. Fully qualified to
      # avoid any future homebrew/cask collision.
      "alexjmiller5/tap/receptor"
      "repobar"
      "slack"
      "spotify"
      "tailscale-app"
      "visual-studio-code"
      "whatsapp"
      "wireshark-app"
      "zoom"
    ];
    # App Store apps (enumerated via `mas list`, 2026-07-28). Requires being
    # signed in to the App Store; mas can't install un-purchased apps.
    # NOTE: cleanup = "zap" does NOT uninstall masApps (brew bundle skips App
    # Store apps; mas has no uninstall). Removing one = delete its line here
    # AND rm the .app manually.
    masApps = {
      "Flappy Golf 2" = 1154174205;
      "Flighty" = 1358823008;
      "Octagon" = 691956219;
      "Telegram" = 747648890;
      "Xcode" = 497799835;
    };

    onActivation.cleanup = "zap";

    # Install every cask without the quarantine xattr — no Gatekeeper
    # first-open prompt for anything brew installs (Alex's call, 2026-08-10).
    caskArgs.no_quarantine = true;
  };
}
