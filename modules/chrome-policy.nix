{
  pkgs,
  lib,
  username,
  ...
}:

# Chrome policy, declared. macOS Chrome reads enterprise policy ONLY from
# /Library/Managed Preferences (root-owned) — policy keys in the normal user
# defaults domain are silently ignored, so this is written by a root
# activation script, not system.defaults. Laptop-only: extensions/PWAs
# are pointless on a headless box. Chrome reloads policy on restart
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
#
# Delivery: macOS's ManagedClient REBUILDS /Library/Managed Preferences from
# installed configuration profiles ~30s after every boot/login (a Screen Time
# internal profile is enough to trigger it), deleting anything not backed by
# a profile — including this plist. So a root LaunchDaemon re-copies it at
# boot and whenever that directory changes (WatchPaths), and the activation
# script uses the same install step so a switch applies it immediately.
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
  normal = {
    installation_mode = "normal_installed";
    update_url = webstore;
  };
  allowed = {
    installation_mode = "allowed";
  };
  # toolbar_pin "force_pinned" = pinned to the toolbar, pin locked
  # (unpinning = remove the attr + switch). Only honored on
  # policy-installed extensions; on `allowed` ones Chrome may ignore it
  # and keep the user's own pin state.
  pin = {
    toolbar_pin = "force_pinned";
  };
  chromePolicy = pkgs.writeText "com.google.Chrome.policy.plist" (
    lib.generators.toPlist { escape = true; } {
      ExtensionSettings =
        lib.optionalAttrs lockdown {
          "*" = {
            installation_mode = "blocked";
            blocked_install_message = "Not declared in nix-config — add it to modules/chrome-policy.nix ExtensionSettings.";
          };
        }
        // {
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = normal // pin; # 1Password – Password Manager
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
        in
        [
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
    }
  );
  # cmp guard: the daemon's own cp would otherwise re-fire WatchPaths forever.
  install = pkgs.writeShellScript "chrome-policy-install" ''
    dir='/Library/Managed Preferences/${username}'
    dst="$dir/com.google.Chrome.plist"
    /bin/mkdir -p "$dir"
    /usr/bin/cmp -s ${chromePolicy} "$dst" && exit 0
    /bin/cp -f ${chromePolicy} "$dst"
    /bin/chmod 644 "$dst"
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';
in
{
  system.activationScripts.postActivation.text = "${install}";

  launchd.daemons.chrome-policy.serviceConfig = {
    ProgramArguments = [ "${install}" ];
    RunAtLoad = true;
    # Both levels: ManagedClient recreates the per-user dir itself, which
    # only the parent's watch is guaranteed to see.
    WatchPaths = [
      "/Library/Managed Preferences"
      "/Library/Managed Preferences/${username}"
    ];
  };
}
