{ config, osConfig, pkgs, lib, username, cherri, ... }:

# Laptop home profile: full shell + dotfiles + the agent-config fan-out.
#
# Two file-management modes in here, chosen per file:
#  - store symlink (home.file.source = ./path): immutable, edit via repo+rebuild.
#    For configs their apps never write (ghostty, karabiner, nvim init).
#  - mkOutOfStoreSymlink: symlink into a live git working copy — tracked, but
#    the app can write at runtime (VS Code settings, Claude settings, skills).
let
  # All companion working clones live in ~/.config (out of iCloud);
  # /etc/nix-darwin symlinks to nixConfig as the canonical rebuild path.
  nixConfig = "${config.home.homeDirectory}/.config/nix-config";
  agentConfig = "${config.home.homeDirectory}/.config/agent-config";
  mkLink = path: config.lib.file.mkOutOfStoreSymlink path;
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
    ./agents.nix
    ./ssh.nix
  ];

  # git-over-https auth (overrides git.nix's gh mkDefault): the fine-grained
  # PAT is read from the "MacBook Air" 1P vault at credential time,
  # authenticated by the agenix-decrypted machine SA token. IDs, not names.
  programs.git.settings.credential."https://github.com".helper =
    "!${pkgs.writeShellScript "git-credential-machine-vault" ''
      [ "$1" = get ] || exit 0
      printf 'username=alexjmiller5\n'
      printf 'password=%s\n' "$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${osConfig.age.secrets.machine-sa.path})" ${pkgs._1password-cli}/bin/op read 'op://a4gdaq4rjdpewl4uppphpjqewm/kxvidplfszmwyaxke6sbwrbl5u/credential')"
    ''}";

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
    # Cherri compiler for the ios-shortcuts project (flake input; not in nixpkgs).
    cherri.packages.${pkgs.stdenv.hostPlatform.system}.default
    # Patches the Spotify cask's client (themes/extensions). Laptop-only: the
    # mini has no Spotify. After any Spotify auto-update, re-run
    # `spicetify restore backup apply`.
    pkgs.spicetify-cli
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

  # yabai config (formula declared in the host; the com.asmvik.yabai launchd
  # agent and the sudoers scripting-addition entry stay manual — MANUAL-macbook-air.md).
  home.file.".yabairc" = {
    source = ../dotfiles/yabai/yabairc;
    executable = true;
  };

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
  home.file."Library/Application Support/com.mitchellh.ghostty/config".source =
    ../dotfiles/ghostty/config;
  xdg.configFile."nvim/init.lua".source = ../dotfiles/nvim/init.lua;
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

  # Hammerspoon profile selector — read by ~/.hammerspoon/init.lua at load.
  # The hammerspoon repo itself stays an independent live clone (never nix-managed).
  home.file.".config/hammerspoon-profile".text = "personal";

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
