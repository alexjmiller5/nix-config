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
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
    ./aliases/infra.nix
    ./macos/menu-bar.nix
    ./macos/spotlight-raycast.nix
    ./macos/nightlight.nix
    ./macos/duti.nix
    ./macos/chrome-extension-shortcuts.nix
    ./ghostty.nix
    ./spotify-player.nix
    ./vscode.nix
    ./agents.nix
    ./ssh.nix
  ];

  # Tab Copy's "Copy selected tabs" shortcut — extension reloads wipe it.
  # command_name comes from the extension's manifest.json "commands" keys.
  chrome.extensionShortcuts = {
    profile = "Profile 1";
    commands."mac:Command+Shift+C" = {
      command_name = "1copy-highlighted-tabs";
      extension = "micdllihgoppmejpecmkilggmaagfdmb";
      global = false;
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
    # gog (Google CLI), wrapped with 1P-ONLY credential storage: no durable
    # local token store. The default macOS keychain backend is structurally
    # broken for nix binaries (adhoc-signed, store path changes every rebuild
    # → keychain ACL invalidated → prompt flood), and Alex wants 1Password as
    # the refresh token's only durable home — so every call rehydrates a
    # throwaway GOG_HOME from the AI Agent vault ("AI Agent Gog OAuth
    # Client" + "AI Agent Gog Token Export" items) and discards it on exit.
    # Same self-auth paradigm as the gh/gcloud wrappers. Cost: ~2 op reads +
    # a Google token refresh per invocation — accepted trade for zero local
    # credential state. A caller-managed GOG_HOME bypasses everything (used
    # by the one-time consent bootstrap; see the gog skill).
    (pkgs.writeShellApplication {
      name = "gog";
      runtimeInputs = [ pkgs._1password-cli ];
      text = ''
        if [ -n "''${GOG_HOME:-}" ]; then
          exec ${gogcliPkg}/bin/gog "$@"
        fi
        ${builtins.readFile ./agent-op-env.sh}
        GOG_HOME="$(mktemp -d "''${TMPDIR:-/tmp}/gog-home-XXXXXX")"
        export GOG_HOME
        trap 'rm -rf "$GOG_HOME"' EXIT
        export GOG_KEYRING_BACKEND=file
        # Ephemeral store → throwaway per-call passphrase.
        GOG_KEYRING_PASSWORD="$(head -c 24 /dev/urandom | base64)"
        export GOG_KEYRING_PASSWORD
        mkdir -p "$GOG_HOME/data"
        op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/4x66lrvreiljbmepa6esgkyu2e/credential' \
          > "$GOG_HOME/data/credentials.json" 2>/dev/null || true
        if op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/jjc6xu22cew46e6zpyfdsdjv3e/credential' \
            > "$GOG_HOME/tokens.json" 2>/dev/null && [ -s "$GOG_HOME/tokens.json" ]; then
          ${gogcliPkg}/bin/gog auth tokens import "$GOG_HOME/tokens.json" >/dev/null 2>&1 || true
          rm -f "$GOG_HOME/tokens.json"
        fi
        ${gogcliPkg}/bin/gog "$@"
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

  # Hammerspoon profile selector — read by ~/.hammerspoon/init.lua at load.
  # The hammerspoon repo itself stays an independent live clone (never nix-managed).
  home.file.".config/hammerspoon-profile".text = "personal";

  # Workspace Snapshot — its flake's home-manager module (imported via
  # sharedModules in flake.nix) installs the Spoon (the hammerspoon repo
  # gitignores that path), the Application Support scripts dir the Claude
  # SessionStart hook references, and the VS Code terminals extension.
  # Replaces the repo's install.sh; updates ride the weekly flake input bump.
  programs.workspace-snapshot.enable = true;

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
