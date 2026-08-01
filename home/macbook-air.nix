{ config, pkgs, lib, username, ... }:

# Laptop home profile: full shell + dotfiles + the agent-config fan-out.
#
# Two file-management modes in here, chosen per file:
#  - store symlink (home.file.source = ./path): immutable, edit via repo+rebuild.
#    For configs their apps never write (ghostty, karabiner, nvim init).
#  - mkOutOfStoreSymlink: symlink into a live git working copy — tracked, but
#    the app can write at runtime (VS Code settings, Claude settings, skills).
let
  repoRoot = "${config.home.homeDirectory}/Desktop/coding/active-projects";
  agentConfig = "${repoRoot}/agent-config";
  mkLink = path: config.lib.file.mkOutOfStoreSymlink path;
in
{
  imports = [
    ./common.nix
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
    ./aliases/infra.nix
    ./macos-tweaks.nix
    ./agents.nix
  ];

  # yabai config (formula declared in the host; the com.asmvik.yabai launchd
  # agent and the sudoers scripting-addition entry stay manual — MANUAL.md).
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
  # Karabiner GUI edits will fail on the read-only file (accepted trade-off);
  # only karabiner.json is managed — assets/ and automatic_backups/ stay real.
  xdg.configFile."karabiner/karabiner.json".source = ../dotfiles/karabiner/karabiner.json;

  # --- VS Code (app-writable → out-of-store into THIS repo's working clone) ---
  home.file."Library/Application Support/Code/User/settings.json".source =
    mkLink "${repoRoot}/nix-config/dotfiles/vscode/settings.json";
  home.file."Library/Application Support/Code/User/keybindings.json".source =
    mkLink "${repoRoot}/nix-config/dotfiles/vscode/keybindings.json";

  # --- agent-config fan-out (private repo; app-writable working copy) ---
  # skills served to BOTH the cross-agent standard location and Claude Code's.
  home.file.".agents/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/settings.json".source = mkLink "${agentConfig}/claude/settings.json";
  home.file.".claude/shell-init.sh".source = mkLink "${agentConfig}/claude/shell-init.sh";
  # AGENTS.md is the agent-agnostic source of truth; CLAUDE.md is its alias.
  home.file.".claude/CLAUDE.md".source = mkLink "${agentConfig}/AGENTS.md";

  # Hammerspoon profile selector — read by ~/.hammerspoon/init.lua at load.
  # The hammerspoon repo itself stays an independent live clone (never nix-managed).
  home.file.".config/hammerspoon-profile".text = "personal";
}
