{ config, osConfig, pkgs, lib, username, cherri, nix-openclaw-tools, ... }:

# Laptop home profile: full shell + dotfiles + the agent-config fan-out.
#
# Two file-management modes in here, chosen per file:
#  - store symlink (home.file.source = ./path): immutable, edit via repo+rebuild.
#    For configs their apps never write and no HM module covers (karabiner).
#  - mkOutOfStoreSymlink: symlink into a live git working copy — tracked, but
#    the app can write at runtime (VS Code settings, Claude settings, skills).
let
  # All companion working clones live in ~/.config (out of iCloud);
  # /etc/nix-darwin symlinks to nixConfig as the canonical rebuild path.
  nixConfig = "${config.home.homeDirectory}/.config/nix-config";
  agentConfig = "${config.home.homeDirectory}/.config/agent-config";
  mkLink = path: config.lib.file.mkOutOfStoreSymlink path;
  # gogcli from the openclaw flake — tracks upstream releases; nixpkgs' copy
  # lags months behind at gog's weekly cadence.
  gogcliPkg = nix-openclaw-tools.packages.${pkgs.stdenv.hostPlatform.system}.gogcli;
in
{
  imports = [
    ./common.nix
    ./op-claude-sa.nix
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
    ./aliases/infra.nix
    ./macos/menu-bar.nix
    ./macos/spotlight-raycast.nix
    ./macos/nightlight.nix
    ./macos/duti.nix
    ./macos/chrome-extension-storage.nix
    ./macos/chrome-remote-debugging.nix
    ./ghostty.nix
    ./spotify-player.nix
    ./vscode.nix
    ./agents.nix
    ./ssh.nix
  ];

  # Keychain claude-code SA token ("op-claude-sa"), refreshed at every login
  # from the machine vault via the machine SA — see home/op-claude-sa.nix.
  opClaudeSa = {
    tokenOpRef = "op://a4gdaq4rjdpewl4uppphpjqewm/qol7eck3fumtefiwyrw4w5m3pm/credential";
    tokenOpAuthFile = osConfig.age.secrets.machine-sa.path;
  };

  # Tab Copy's ⇧⌘C shortcut is NOT codified: it lives in Chrome's HMAC-signed
  # Secure Preferences (extensions.settings.<id>.commands), so an unsigned
  # external write is ignored on startup. Re-bind it by hand after an
  # extension reload — see MANUAL-macbook-air.md.

  # Lets CDP clients attach to the real logged-in Chrome (the chrome-control
  # skill's Tier 2); each connection still needs a manual "Allow" click.
  chrome.remoteDebugging.enable = true;

  # Tab Copy's custom "URL Format" (urls only, newline-delimited) — lives in
  # the extension's chrome.storage.local, wiped on reinstall. Captured from a
  # live plyvel dump 2026-08-18; edit here (or re-dump) after UI changes,
  # since these values are enforced over UI edits at every switch.
  chrome.extensionStorage = {
    profile = "Profile 1";
    storage.micdllihgoppmejpecmkilggmaagfdmb = {
      customFormatIds = [ "custom-9hVL4q" ];
      orderedFormatIds = [ "custom-9hVL4q" ];
      hiddenFormatIds = [ ];
      formatOpts."custom-9hVL4q" = {
        name = "URL Format";
        template = {
          start = "";
          end = "";
          tab = "[url]";
          tabDelimiter = "[n]";
          windowStart = "";
          windowEnd = "";
          windowDelimiter = "[n]";
        };
      };
    };
  };

  # git-over-https auth, split by repo (2026-08-10; discovered when the
  # osxkeychain neutralization exposed that general pushes had been riding a
  # cached keychain token):
  #  - agent-config + nix-secrets: the machine-vault fine-grained PAT
  #    (contents:write on exactly those two repos), read at credential time
  #    via the agenix-decrypted machine SA — headless, so the launchd sync
  #    agents keep working. IDs, not names.
  #  - everything else: git.nix's `gh auth git-credential` default, which is
  #    the op-authed gh PATH wrapper — desktop-app auth in Alex's terminals,
  #    SA token in agent shells. The machine PAT is deliberately NOT write-
  #    broadened; general pushes belong to the gh PAT.
  # useHttpPath makes git consult the repo-scoped helper keys; the .git
  # suffix is REQUIRED — path matching is exact and the remotes carry it.
  programs.git.settings.credential =
    let
      machineVault = "!${pkgs.writeShellScript "git-credential-machine-vault" ''
        [ "$1" = get ] || exit 0
        printf 'username=alexjmiller5\n'
        printf 'password=%s\n' "$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${osConfig.age.secrets.machine-sa.path})" ${pkgs._1password-cli}/bin/op read 'op://a4gdaq4rjdpewl4uppphpjqewm/kxvidplfszmwyaxke6sbwrbl5u/credential')"
      ''}";
    in {
      "https://github.com".useHttpPath = true;
      "https://github.com/alexjmiller5/agent-config.git".helper = machineVault;
      "https://github.com/alexjmiller5/nix-secrets.git".helper = machineVault;
    };

  # Keep ~/Desktop materialized (never iCloud-evicted) — symlink targets and
  # working clones live under it. Laptop-personal, so not a home/macos module.
  home.activation.pinDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(/usr/bin/xattr -p com.apple.fileprovider.pinned "$HOME/Desktop" 2>/dev/null)" != "1" ]; then
      /usr/bin/xattr -w com.apple.fileprovider.pinned 1 "$HOME/Desktop"
    fi
  '';

  # Menu bar system-module ORDER (right → left below). ControlCenter honors
  # relative "Preferred Position" plain-domain values at launch (macOS 26,
  # verified 2026-08-04). On-demand command, not activation: ControlCenter
  # renormalizes the numbers after layout, so enforcing exact values every
  # switch would flap. Third-party icon order stays manual (⌘-drag) — see
  # MANUAL-macbook-air.md.
  home.packages = [
    # Migrated from the laptop brews list 2026-08-10 (nixpkgs-first rule).
    # Laptop-scoped like the brews were — not cli-tools.nix, which both hosts
    # and the work-laptop export share.
    pkgs.bun
    pkgs.create-dmg
    # VS Code's editor font — home-manager copies package fonts into
    # ~/Library/Fonts/HomeManager. Replaces the hand-installed ttfs.
    pkgs.fira-code
    pkgs.duti
    pkgs.exiftool
    pkgs.fastlane
    pkgs.ffmpeg
    # gog (Google CLI), wrapped with 1P-ONLY credential storage: gog itself
    # never sees a refresh token and nothing credential-shaped touches disk.
    # The wrapper owns the OAuth refresh: the "AI Agent Gog Token Export"
    # item holds the refresh token (credential field, `gog auth tokens
    # export` JSON) plus a cached access_token/expires_at pair the wrapper
    # writes back after each refresh; "AI Agent Gog OAuth Client" holds the
    # client JSON. Fast path (access token still valid) = ONE op call, no
    # Google round-trip; slow path (~hourly) = curl refresh + 1P writeback.
    # gog runs in --access-token mode throughout (bypasses stored tokens).
    # The macOS keychain backend stays banned: structurally broken for nix
    # binaries (adhoc-signed, store path changes each rebuild → ACL prompt
    # flood). Caller-set GOG_ACCESS_TOKEN or GOG_HOME bypasses everything
    # (the consent bootstrap uses GOG_HOME; see the gog skill).
    (pkgs.writeShellApplication {
      name = "gog";
      runtimeInputs = [ pkgs._1password-cli pkgs.jq pkgs.curl ];
      text = ''
        if [ -n "''${GOG_ACCESS_TOKEN:-}''${GOG_HOME:-}" ]; then
          exec ${gogcliPkg}/bin/gog "$@"
        fi
        ${builtins.readFile ./agent-op-env.sh}
        item="$(op item get jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm --format json 2>/dev/null || true)"
        if [ -n "$item" ]; then
          at="$(jq -r '[.fields[] | select(.label == "access_token")][0].value // empty' <<<"$item")"
          exp="$(jq -r '[.fields[] | select(.label == "expires_at")][0].value // empty' <<<"$item")"
          case "$exp" in ("" | *[!0-9]*) exp=0 ;; esac
          now="$(date +%s)"
          if [ -n "$at" ] && [ "$now" -lt "$((exp - 60))" ]; then
            export GOG_ACCESS_TOKEN="$at"
            exec ${gogcliPkg}/bin/gog "$@"
          fi
          # Access token missing/expired: refresh it ourselves and cache it
          # back into the item. Secrets travel via stdin, never argv.
          rt="$(jq -r '[.fields[] | select(.id == "credential")][0].value // empty' <<<"$item" | jq -r '.refresh_token // empty' 2>/dev/null || true)"
          client="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/4x66lrvreiljbmepa6esgkyu2e/credential' 2>/dev/null || true)"
          cid="$(jq -r '.installed.client_id // .web.client_id // empty' <<<"$client" 2>/dev/null || true)"
          csec="$(jq -r '.installed.client_secret // .web.client_secret // empty' <<<"$client" 2>/dev/null || true)"
          if [ -n "$rt" ] && [ -n "$cid" ]; then
            resp="$(printf 'grant_type=refresh_token&client_id=%s&client_secret=%s&refresh_token=%s' "$cid" "$csec" "$rt" \
              | curl -s --max-time 30 --data @- https://oauth2.googleapis.com/token || true)"
            at="$(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null || true)"
            expin="$(jq -r '.expires_in // 3600' <<<"$resp" 2>/dev/null || echo 3600)"
            if [ -n "$at" ]; then
              op item edit jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm \
                "access_token[concealed]=$at" "expires_at[text]=$((now + expin))" >/dev/null 2>&1 || true
              export GOG_ACCESS_TOKEN="$at"
            else
              # invalid_grant = refresh token revoked (password change / 6mo
              # idle / consent withdrawn) → human re-consent is the only fix.
              err="$(jq -r '.error // empty' <<<"$resp" 2>/dev/null || true)"
              echo "gog wrapper: token refresh failed (''${err:-no response from Google}) — refresh token likely revoked. Fix: Alex runs \`gog-auth-bootstrap\` in his own terminal (alias; script in the gog skill)." >&2
            fi
          fi
        fi
        exec ${gogcliPkg}/bin/gog "$@"
      '';
    })
    pkgs.libimobiledevice
    pkgs.mas
    pkgs.nodejs
    pkgs.oci-cli
    pkgs.pnpm
    pkgs.terraform # unfree (BSL) — allowed in hosts/macbook-air.nix predicate
    pkgs.wrangler # brew name: cloudflare-wrangler
    pkgs.xcodegen
    pkgs.yt-dlp
    # gcloud, ALWAYS authed via 1Password (GCP SA key item in the AI Agent
    # vault) — same paradigm as the gh wrapper in scripts.nix, laptop-only
    # because the mini has no GCP use. Replaces the brew gcloud-cli cask and
    # the interactive-only op plugin alias so scripts/launchd/agent shells
    # are authed too. The key JSON transits a 0600 mktemp file removed on
    # exit (same mechanism `op plugin run` uses internally).
    (pkgs.writeShellApplication {
      name = "gcloud";
      runtimeInputs = [ pkgs._1password-cli ];
      text = ''
        if [ -n "''${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE:-}''${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
          exec ${pkgs.google-cloud-sdk}/bin/gcloud "$@"
        fi
        ${builtins.readFile ./agent-op-env.sh}
        keyfile="$(mktemp "''${TMPDIR:-/tmp}/gcloud-key-XXXXXX")"
        trap 'rm -f "$keyfile"' EXIT
        if op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/iqywn6he6twhyonw3fhnqmot5i/credential' > "$keyfile" 2>/dev/null && [ -s "$keyfile" ]; then
          export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="$keyfile"
        fi
        ${pkgs.google-cloud-sdk}/bin/gcloud "$@"
      '';
    })
    # memo (Apple Notes CLI, antoniorodr/memo) — needed by the apple-notes /
    # triage-apple-notes agent skills. Not in nixpkgs, and its brew formula's
    # python was broken on this machine, so run it uv-style: uvx resolves from
    # git once and reuses the cached env (refresh = `uvx --refresh --from … memo`).
    # Replaces the imperative `uv tool install` copy in ~/.local/bin.
    (pkgs.writeShellApplication {
      name = "memo";
      runtimeInputs = [ pkgs.uv ];
      text = ''
        exec uvx --from git+https://github.com/antoniorodr/memo memo "$@"
      '';
    })
    # Tailscale CLI for the GUI app (tailscale-app cask ships no PATH binary) —
    # replaces the hand-written /usr/local/bin/tailscale shim.
    (pkgs.writeShellApplication {
      name = "tailscale";
      text = ''
        exec "/Applications/Tailscale.app/Contents/MacOS/Tailscale" "$@"
      '';
    })
    # Cherri compiler for the ios-shortcuts project (flake input; not in nixpkgs).
    cherri.packages.${pkgs.stdenv.hostPlatform.system}.default
    # EGGNOGG+ (madgarden.itch.io/eggnogg) — itch.io-only, served via signed
    # expiring URLs, so no cask/plain-fetchurl is possible. The fixed-output
    # src derivation replays itch's anonymous download dance (csrf → POST →
    # signed URL) at fetch time; the pinned hash keeps it reproducible. Build
    # unchanged since 2015 (upload 138870); x86_64-only, needs Rosetta.
    # Lands in ~/Applications/Home Manager Apps.
    (let
      zip = pkgs.stdenvNoCC.mkDerivation {
        name = "eggnoggplus-osx.zip";
        nativeBuildInputs = [ pkgs.curl pkgs.cacert ];
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        buildCommand = ''
          csrf=$(curl -s -c cookies.txt https://madgarden.itch.io/eggnogg \
            | grep -oE 'csrf_token" value="[^"]+' | cut -d'"' -f3)
          url=$(curl -s -b cookies.txt -X POST \
            "https://madgarden.itch.io/eggnogg/file/138870?source=game_download" \
            --data-urlencode "csrf_token=$csrf" \
            | grep -oE '"url":"[^"]+' | cut -d'"' -f4 | sed 's|\\/|/|g')
          curl -sL "$url" -o "$out"
        '';
        outputHashAlgo = "sha256";
        outputHashMode = "flat";
        outputHash = "sha256-u3/eKr4/jG44DUV9UMK5kcfm/98Fnhh2obt/Wwl341U=";
      };
    in pkgs.stdenvNoCC.mkDerivation {
      pname = "eggnoggplus";
      version = "1.0";
      src = zip;
      nativeBuildInputs = [ pkgs.unzip ];
      unpackPhase = "unzip -q $src";
      installPhase = ''
        mkdir -p $out/Applications
        cp -R eggnoggplus.app $out/Applications/
      '';
    })
    (pkgs.writeShellApplication {
      name = "menubar-layout";
      text = ''
        pos=110
        for mod in Sound WiFi Battery Bluetooth ScreenMirroring AirDrop; do
          /usr/bin/defaults write com.apple.controlcenter \
            "NSStatusItem Preferred Position $mod" -int "$pos"
          pos=$((pos + 50))
        done
        /usr/bin/killall ControlCenter 2>/dev/null || true
        echo "system modules re-laid out, right→left: Sound WiFi Battery Bluetooth ScreenMirroring AirDrop"
      '';
    })
  ];

  # Commit signing via 1Password (desktop app + op-ssh-sign, laptop-only).
  # The signer script lives in agent-config, reached via the ~/.claude/skills
  # symlink so the path stays stable if the repo moves.
  programs.git.settings = {
    user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKWqJ5X61r/CFl99qjU/rZyIB4DCQpVI+cF0y33WSSMC";
    gpg.format = "ssh";
    gpg.ssh.program = "${config.home.homeDirectory}/.claude/skills/1password/scripts/op-ssh-sign-auto";
    commit.gpgsign = true;
  };

  home.file.".hushlogin".text = "";

  # --- static dotfiles (read-only; edit in dotfiles/ + rebuild) ---
  # Finder quick action (right-click → Open in VS Code). pbs auto-registers
  # anything in ~/Library/Services; no further wiring needed.
  home.file."Library/Services/Open in VS Code.workflow".source =
    ../dotfiles/services + "/Open in VS Code.workflow";
  xdg.configFile."karabiner/karabiner.json".source = ../dotfiles/karabiner/karabiner.json;

  # --- VS Code (app-writable → out-of-store into THIS repo's working clone) ---
  home.file."Library/Application Support/Code/User/settings.json".source =
    mkLink "${nixConfig}/dotfiles/vscode/settings.json";
  home.file."Library/Application Support/Code/User/keybindings.json".source =
    mkLink "${nixConfig}/dotfiles/vscode/keybindings.json";

  # --- agent-config fan-out (private repo; app-writable working copy) ---
  # skills served to BOTH the cross-agent standard location and Claude Code's.
  home.file.".agents/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/settings.json".source = mkLink "${agentConfig}/claude/settings.json";
  home.file.".claude/shell-init.sh".source = mkLink "${agentConfig}/claude/shell-init.sh";
  home.file.".claude/hooks".source = mkLink "${agentConfig}/claude/hooks";
  home.file.".claude/CLAUDE.md".source = mkLink "${agentConfig}/AGENTS.md";
  home.file.".claude/statusline.sh".source = mkLink "${agentConfig}/claude/statusline.sh";

  # Claude auto-memory lives in agent-config/memory/<cwd-slug>/, adopted and
  # linked by the agent-config-sync agent (home/agents.nix) — not here, so
  # adoption happens before that agent's commit rather than only at switch.

  # Hammerspoon profile selector — read by ~/.hammerspoon/init.lua at load.
  # The hammerspoon repo itself stays an independent live clone (never nix-managed).
  home.file.".config/hammerspoon-profile".text = "personal";

  # Workspace Snapshot — its flake's home-manager module (imported via
  # sharedModules in flake.nix) installs the Application Support scripts dir
  # the Claude SessionStart hook references and the VS Code terminals
  # extension. Replaces the repo's install.sh; updates ride the weekly flake
  # input bump. The Spoon itself is NOT symlinked anymore: the hammerspoon
  # repo vendors all spoons in-tree (real dir at the same path), so the
  # module's spoon file is disabled here.
  programs.workspace-snapshot.enable = true;
  home.file.".hammerspoon/Spoons/WorkspaceSnapshot.spoon".enable = false;

  # Companion working clones — clone-if-missing at activation. Makes the
  # MANUAL clone steps self-healing: a fresh machine bootstraps from a local
  # clone (MANUAL §3 — the machine-sa secret must be recreated first), and
  # the first switch materializes the rest. Private clones auth via the
  # machine-vault credential helper; on failure they warn and skip —
  # re-run switch once the machine-sa secret decrypts.
  home.activation.companionRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/opt/homebrew/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
    companionClone() {
      [ -d "$2" ] || /usr/bin/git clone --quiet "https://github.com/alexjmiller5/$1.git" "$2" \
        || echo "companion-repos: clone of $1 failed — machine-sa decrypted? op reachable? re-run switch" >&2
    }
    companionClone nix-config "${nixConfig}"
    companionClone nix-secrets "${config.home.homeDirectory}/.config/nix-secrets"
    companionClone agent-config "${agentConfig}"
    companionClone hammerspoon "${config.home.homeDirectory}/.hammerspoon"
  '';
}
