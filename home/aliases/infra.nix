# Personal-infrastructure aliases — Alex's machines/filesystem layout only.
# A work host should NOT import this file.
{ config, ... }:
let
  just = "just --justfile /etc/nix-darwin/justfile";
  onMini = config.agentMachine.profile == "mini";
in
{
  programs.zsh.shellAliases = {
    coding = "cd ~/Desktop/coding";
    projects = "cd ~/Desktop/coding/active-projects";
    inactive-projects = "cd ~/Desktop/coding/inactive-projects";

    # /etc/nix-darwin is the canonical path to the nix-config clone - these
    # survive the clone moving again. Each alias applies ITS host: locally when
    # this machine is that host, otherwise by pushing the flake over ssh
    # (justfile deploy), so neither machine ever sshes into itself.
    switch-macbook =
      if onMini then "${just} deploy macbook-air-tailscale macbook-air" else "${just} switch-laptop";
    switch-mini = if onMini then "${just} switch" else "${just} deploy";

    # alias/function source now lives in nix-config (rebuild to apply edits)
    valiases = "nvim /etc/nix-darwin/home/aliases";
    vfuncs = "nvim /etc/nix-darwin/home/zsh/functions.zsh";
    cfuncs = "cat /etc/nix-darwin/home/zsh/functions.zsh";
  };
}
