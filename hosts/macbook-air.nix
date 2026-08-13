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

  # Chrome extensions, declared (enterprise-policy plist read by Chrome —
  # the list IS the extension set: entries force-install from the Web Store,
  # auto-update, and can't be removed in the UI; removing a line here
  # uninstalls the extension after the next switch + Chrome restart.
  # Unpacked/dev extensions (own tools, bypass-paywalls) are NOT policy-
  # installable — those stay manual, see MANUAL-macbook-air.md.
  # NOTE: laptop-only — the mini's Chrome (finance scrapers) must stay bare.
  system.defaults.CustomUserPreferences."com.google.Chrome" = {
    ExtensionInstallForcelist = [
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1Password – Password Manager
      "gighmmpiobklfepjocnamgkkbiglidom" # AdBlock
      "efaidnbmnnnibpcajpcglclefindmkaj" # Adobe Acrobat
      "kfaknphcidikmjhmmfmphghhlcoknflj" # Amazon Unsponsor
      "kagpmnfgpdecdkbhongbgkgppnpimime" # Bookmarks Exporter
      "iiikidmnimlpahbeknmkeonmemajpccj" # Button Stealer
      "cbhilkcodigmigfbnphipnnmamjfkipp" # Calendly
      "nenlahapcbofgnanklpelkaejcehkggg" # Capital One Shopping
      "ejcfepkfckglbgocfkanmcdngdijcgld" # ChatGPT search
      "fcoeoabgfenejglbffodgkkbkcdhcgfn" # Claude
      "fcalilbnpkfikdppppppchmkdipibalb" # Cloaq
      "ifjhcahbhkfojdmkndpkmkffbjnefido" # Cookie Guard
      "jlmpjdjjbgclbocgajdjefcidcncaied" # daily.dev | Where developers discover what's next
      "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
      "gdkfehnloabjkmccddnjckpnlhcdcalh" # De-Sponsor for Amazon
      "cnpgabmfnfehdamobkafalnpdoigdlil" # FaviGrab
      "hnmpcagpplmpfojmgmnngilcnanddlhb" # Free VPN For Chrome
      "kfgepjmmgamniaefbjlbacahkjjnjoaa" # Gmail reverse conversation
      "jgjaapljoafhkohbnfigoekjgdfddnnn" # Gmail Show Time
      "fdpohaocaechififmbbbbbknoalclacl" # GoFullPage
      "mgijmajocgfcbeboacabfgobmjgjcoja" # Google Dictionary (by Google)
      "ghbmnnjooekpmoecnnnilnnbdlolhkhi" # Google Docs Offline
      "aapbdbdomjkkjkaonfhkkikfgjllcleb" # Google Translate
      "gjbnlmbnepomgkknbhclokdameangdan" # Insta Content Blocker
      "bcjindcccaagfpapjjmafapmmgkkhgoa" # JSON Formatter
      "chklaanhfefbnpoihckbnefhakgolnmc" # JSONVue
      "dijpdmknlincdehpemajfobhfcmjkhof" # LinkedIn Feed Blocker
      "iepgempfdndmbciedjdladndpoeodepl" # Lovable Project Downloader
      "nkbihfbeogaeaoehlefnkodbefgpgknn" # MetaMask
      "pobhoodpcipjmedfenaigbeloiidbflp" # Minimal Theme for Twitter / X
      "knheggckgoiihginacbkhaalnibhilkk" # Notion Web Clipper
      "bkhaagjahfmjljalopjnoealnfndnagc" # Octotree
      "jlgojbammkhdbbohlihccohgbaccgpbm" # Open Links in Tabs
      "chhjbpecpncaggjpdakmflnfcopglcmi" # Rakuten
      "fgacdjnoljjfikkadhogeofgjoglooma" # Raycast Companion
      "fmkadmapgofadopljbjfkapdkoienihi" # React Developer Tools
      "mmnhjecbajmgkapcinkhdnjabclcnfpg" # Reddit Promoted Ad Blocker
      "hlepfoohegkhhmjieoechaddaejaokhf" # Refined GitHub
      "gebbhagfogifgggkldgodflihgfeippi" # Return YouTube Dislike
      "bnhjfbjmbgmgllkojikabliaidpihfnp" # Reverbify
      "mpdajninpobndbfcldcmbpnnbhibjmch" # SAML-tracer
      "gmbmikajjgmnabiglmofipeabaddhgne" # Save to Google Drive
      "pbanhockgagggenencehbnadejlgchfc" # Simplify Copilot
      "mnjggcdmjocbbbhaepdhchncahnbgone" # SponsorBlock for YouTube
      "nfmlkliedggdodlbgghmmchhgckjoaml" # Spotify Ad Blocker
      "bgehnoihoklmofgehcefiaicdcdgppck" # Spotify Playback Speed
      "jcgpgjhaendighananonflfmjjefjjlp" # Streak Email Tracking for Gmail
      "pdmhehfogekmpmdoemhabjpaiadagpgp" # Student Beans
      "micdllihgoppmejpecmkilggmaagfdmb" # Tab Copy
      "dhdgffkkebhmkfjojejmpbldmpobfkfo" # Tampermonkey
      "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
      "pmbneaajfhcoecedlmkfkdnjemmebbcb" # UnSponsored
      "djflhoibgkdhkhhcedjiklpkjnoahfmg" # User-Agent Switcher for Chrome
      "dbepggeogbaibhgnhhndojpepiihcmeb" # Vimium
      "bfbameneiokkgbdmiekhjnmfkcnldhhm" # Web Developer
      "ppaojnbmmaigjmlpjaldnkgnklhicppk" # Webtime Tracker
      "jabopobgcpjmedljpbcaablpmlmfcogm" # WhatFont
      "jiaopdjbehhjgokpphdfgmapkobbnmjp" # Youtube-shorts block
    ];

    # PWAs, declared (same policy plist). Force-installed per profile at
    # Chrome launch; the ~/Applications/Chrome Apps.localized/<Name>.app
    # shims (dock references Google Maps.app) are created on install and
    # can't be uninstalled in the UI while listed here.
    WebAppInstallForceList = [
      { url = "https://secure.bankofamerica.com/myaccounts/signin/signIn.go"; default_launch_container = "window"; }
      { url = "https://contacts.google.com/"; default_launch_container = "window"; }
      { url = "https://www.google.com/maps"; default_launch_container = "window"; }
      { url = "https://translate.google.com/"; default_launch_container = "window"; }
      { url = "https://web.groupme.com/"; default_launch_container = "window"; }
      { url = "https://www.instagram.com/"; default_launch_container = "window"; }
      { url = "https://www.linkedin.com/feed/"; default_launch_container = "window"; }
      { url = "https://settleup.app/"; default_launch_container = "window"; }
      { url = "https://www.snapchat.com/web"; default_launch_container = "window"; }
      { url = "https://login.tailscale.com/admin"; default_launch_container = "window"; }
      { url = "https://account.venmo.com/"; default_launch_container = "window"; }
      { url = "https://www.wordreference.com/enes/"; default_launch_container = "window"; }
      { url = "https://x.com/"; default_launch_container = "window"; }
      { url = "https://www.youtube.com"; default_launch_container = "window"; }
    ];
  };

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
