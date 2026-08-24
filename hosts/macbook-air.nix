{ config, pkgs, lib, username, ... }:

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

  # yabai: the org.nixos.yabai launchd agent runs the nix package for BSP
  # tiling. The scripting addition is OFF — macOS 26.1's AMFI enforces library
  # validation on Dock (a platform binary) and refuses to load yabai's
  # third-party ad-hoc payload, so SA-only features (space create/destroy,
  # cross-display space moves, opacity, sticky windows) don't work regardless
  # of SIP state. With the SA off there's no yabai-sa daemon and no
  # /etc/sudoers.d/yabai. Still manual: granting Accessibility when the store
  # path changes on upgrades (MANUAL-macbook-air.md). Revisit if yabai ships
  # real macOS 26.x injection support.
  #
  # config.layout is set purely so the module writes a yabairc and passes
  # `-c` — without any config yabai warns "could not locate config file" on
  # every start. `float` matches yabai's own default (no auto-tiling); switch
  # to "bsp" here for automatic tiling.
  services.yabai = {
    enable = true;
    config.layout = "float";
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
  # ExtensionSettings + default-deny — the Chrome analog of brew's zap: the
  # ACTIVE lines below ARE the extension set; anything undeclared ("*"
  # blocked) cannot be installed, store or sideload. Active entries are
  # normal_installed: auto-installed from the store, auto-updating, no UI
  # uninstall — but the enable/disable TOGGLE stays manual on purpose (a
  # broken extension — 1Password has done this — must be switch-off-able
  # without a rebuild). The OFF switch is the comment marker: a commented
  # entry is blocked like anything undeclared (an existing install gets
  # policy-disabled; fresh machines never see it); uncomment + switch =
  # installed and usable.
  # Exception: unpacked/dev extensions need "allowed" entries by their
  # path-derived IDs for Load-unpacked to work under the blocked default
  # (a moved source dir mints a new ID — update the entry).
  system.activationScripts.postActivation.text =
    let
      # AIRLOCK for unpacked extensions: Chrome cannot exempt Load-unpacked
      # per-ID — with "*" blocked it is refused wholesale ("Extension
      # installation is blocked by policy"); the per-ID allowed entries only
      # keep ALREADY-LOADED unpacked extensions alive. Installing a new one:
      #   1. lockdown = false → switch → restart Chrome
      #   2. chrome://extensions → Load unpacked (and add the path-derived ID
      #      as an `allowed` entry below so it survives re-lock)
      #   3. lockdown = true → switch → restart Chrome
      lockdown = true;
      webstore = "https://clients2.google.com/service/update2/crx";
      normal = { installation_mode = "normal_installed"; update_url = webstore; };
      allowed = { installation_mode = "allowed"; };
      # toolbar_pin "force_pinned" = pinned to the toolbar, pin locked
      # (unpinning = remove the attr + switch). Only honored on
      # policy-installed extensions; on `allowed` ones Chrome may ignore it
      # and keep the user's own pin state.
      pin = { toolbar_pin = "force_pinned"; };
      chromePolicy = pkgs.writeText "com.google.Chrome.policy.plist" (lib.generators.toPlist { escape = true; } {
        ExtensionSettings = lib.optionalAttrs lockdown {
          "*" = {
            installation_mode = "blocked";
            blocked_install_message = "Not declared in nix-config — add it to hosts/macbook-air.nix ExtensionSettings.";
          };
        } // {
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = normal; # 1Password – Password Manager
          # "gighmmpiobklfepjocnamgkkbiglidom" = normal; # AdBlock (off — uncomment to install)
          # "efaidnbmnnnibpcajpcglclefindmkaj" = normal; # Adobe Acrobat (off — uncomment to install)
          "kfaknphcidikmjhmmfmphghhlcoknflj" = normal; # Amazon Unsponsor
          "kagpmnfgpdecdkbhongbgkgppnpimime" = normal; # Bookmarks Exporter
          "iiikidmnimlpahbeknmkeonmemajpccj" = normal; # Button Stealer
          # "cbhilkcodigmigfbnphipnnmamjfkipp" = normal; # Calendly (off — uncomment to install)
          # "nenlahapcbofgnanklpelkaejcehkggg" = normal; # Capital One Shopping (off — uncomment to install)
          # "ejcfepkfckglbgocfkanmcdngdijcgld" = normal; # ChatGPT search (off — uncomment to install)
          "fcoeoabgfenejglbffodgkkbkcdhcgfn" = normal; # Claude
          "fcalilbnpkfikdppppppchmkdipibalb" = normal; # Cloaq
          # "ifjhcahbhkfojdmkndpkmkffbjnefido" = normal; # Cookie Guard (off — uncomment to install)
          # "jlmpjdjjbgclbocgajdjefcidcncaied" = normal; # daily.dev | Where developers discover what's next (off — uncomment to install)
          # "eimadpbcbfnmbkopoojfekhnkhdbieeh" = normal; # Dark Reader (off — uncomment to install)
          "gdkfehnloabjkmccddnjckpnlhcdcalh" = normal; # De-Sponsor for Amazon
          "cnpgabmfnfehdamobkafalnpdoigdlil" = normal; # FaviGrab
          # "hnmpcagpplmpfojmgmnngilcnanddlhb" = normal; # Free VPN For Chrome (off — uncomment to install)
          "kfgepjmmgamniaefbjlbacahkjjnjoaa" = normal; # Gmail reverse conversation
          "jgjaapljoafhkohbnfigoekjgdfddnnn" = normal; # Gmail Show Time
          "mgijmajocgfcbeboacabfgobmjgjcoja" = normal; # Google Dictionary (by Google)
          "ghbmnnjooekpmoecnnnilnnbdlolhkhi" = normal; # Google Docs Offline
          "aapbdbdomjkkjkaonfhkkikfgjllcleb" = normal; # Google Translate
          "gjbnlmbnepomgkknbhclokdameangdan" = normal; # Insta Content Blocker
          "bcjindcccaagfpapjjmafapmmgkkhgoa" = normal; # JSON Formatter
          "chklaanhfefbnpoihckbnefhakgolnmc" = normal; # JSONVue
          "dijpdmknlincdehpemajfobhfcmjkhof" = normal; # LinkedIn Feed Blocker
          # "iepgempfdndmbciedjdladndpoeodepl" = normal; # Lovable Project Downloader (off — uncomment to install)
          "nkbihfbeogaeaoehlefnkodbefgpgknn" = normal; # MetaMask
          "pobhoodpcipjmedfenaigbeloiidbflp" = normal; # Minimal Theme for Twitter / X
          "knheggckgoiihginacbkhaalnibhilkk" = normal; # Notion Web Clipper
          "bkhaagjahfmjljalopjnoealnfndnagc" = normal; # Octotree
          # "jlgojbammkhdbbohlihccohgbaccgpbm" = normal; # Open Links in Tabs (off — uncomment to install)
          # "chhjbpecpncaggjpdakmflnfcopglcmi" = normal; # Rakuten (off — uncomment to install)
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
          # "bgehnoihoklmofgehcefiaicdcdgppck" = normal; # Spotify Playback Speed (off — uncomment to install)
          "jcgpgjhaendighananonflfmjjefjjlp" = normal; # Streak Email Tracking for Gmail
          # "pdmhehfogekmpmdoemhabjpaiadagpgp" = normal; # Student Beans (off — uncomment to install)
          "micdllihgoppmejpecmkilggmaagfdmb" = normal // pin; # Tab Copy
          "dhdgffkkebhmkfjojejmpbldmpobfkfo" = normal; # Tampermonkey
          "ddkjiahejlhfcafbddmgiahcphecmpfh" = normal // pin; # uBlock Origin Lite
          "pmbneaajfhcoecedlmkfkdnjemmebbcb" = normal; # UnSponsored
          "djflhoibgkdhkhhcedjiklpkjnoahfmg" = normal; # User-Agent Switcher for Chrome
          # "dbepggeogbaibhgnhhndojpepiihcmeb" = normal; # Vimium (off — uncomment to install)
          "bfbameneiokkgbdmiekhjnmfkcnldhhm" = normal; # Web Developer
          "ppaojnbmmaigjmlpjaldnkgnklhicppk" = normal; # Webtime Tracker
          "jabopobgcpjmedljpbcaablpmlmfcogm" = normal; # WhatFont
          "jiaopdjbehhjgokpphdfgmapkobbnmjp" = normal; # Youtube-shorts block

          # Unpacked / dev-mode (path-derived IDs, see header):
          "lkbebcjgcmobigpeffafkodonchffocl" = allowed // pin; # bypass-paywalls-chrome-clean (built-from-source)
          "ogjfmlhndbkglaiednoodaeceffhpnha" = allowed; # lovable-downloader (active-projects)
        };

        # Google's built-in password / payment / address managers OFF —
        # 1Password owns all three. Also removes their entries from
        # Customize Chrome → Toolbar and kills the "save in Google?" prompts.
        PasswordManagerEnabled = false;
        AutofillCreditCardEnabled = false;
        AutofillAddressEnabled = false;

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
            (app "https://www.facebook.com/messages" "Messenger")
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
      # Rosetta 2, declared (needed by EGGNOGG+ in home/macbook-air.nix —
      # x86_64-only). No nix-darwin option exists; activation runs as root,
      # so install here, guarded by the oahd check to stay idempotent.
      if ! /usr/bin/pgrep -q oahd; then
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license
      fi

      mkdir -p '/Library/Managed Preferences/${username}'
      cp -f ${chromePolicy} '/Library/Managed Preferences/${username}/com.google.Chrome.plist'
      chmod 644 '/Library/Managed Preferences/${username}/com.google.Chrome.plist'
      /usr/bin/killall cfprefsd 2>/dev/null || true

      # De-quarantine declared casks — successor to brew's removed
      # --no-quarantine (Homebrew/brew#20755). Runs after brew bundle
      # (postActivation is last), so freshly installed casks are covered.
      # Scoped to brew-managed apps via the Caskroom app symlinks on
      # purpose: anything else in /Applications keeps its Gatekeeper
      # prompt. Quarantine-flag check on the bundle root keeps re-runs
      # cheap (no recursive walk unless there's something to strip).
      for link in /opt/homebrew/Caskroom/*/*/*.app; do
        app=$(/usr/bin/readlink "$link" || echo "$link")
        if [ -e "$app" ] && /usr/bin/xattr -p com.apple.quarantine "$app" >/dev/null 2>&1; then
          echo "de-quarantining $app" >&2
          /usr/bin/xattr -dr com.apple.quarantine "$app"
        fi
      done

      # yabai TCC reminder: Accessibility grants key on the nix store path,
      # which changes on version bumps — the old grant dies and the keepalive
      # agent spams Accessibility prompts (MANUAL-macbook-air.md). Compare
      # against the last-switched path and print re-grant instructions.
      yabaiBin='${config.services.yabai.package}/bin/yabai'
      if [ "$(cat /var/db/yabai-tcc-path 2>/dev/null)" != "$yabaiBin" ]; then
        printf '\n\033[1;33myabai store path changed — re-grant Accessibility or the prompt spam returns:\033[0m\n'
        echo "  System Settings > Privacy & Security > Accessibility:"
        echo "    1. remove the stale yabai row (minus button)"
        echo "    2. + > Cmd+Shift+G > paste: $yabaiBin"
        echo "    3. toggle it ON"
        echo "$yabaiBin" > /var/db/yabai-tcc-path
      fi
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
    # trusted = true feeds Homebrew's tap-trust store at activation — without
    # it brew ignores the tap's formulae/casks entirely.
    taps = [
      # Alex's personal cask tap — apps released by their repos' CI
      # (gemini-desktop, receptor, ...).
      { name = "alexjmiller5/tap"; trusted = true; }
      { name = "smudge/smudge"; trusted = true; }
      { name = "steipete/tap"; trusted = true; }
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
      "pearcleaner"
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

    # No caskArgs.no_quarantine: Homebrew 6's brew bundle passes it malformed
    # (--no_quarantine, fails every new cask install) and the flag is removed
    # upstream on 2026-09-01. New casks get the one-time Gatekeeper prompt.
  };
}
