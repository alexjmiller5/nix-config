{ config, lib, ... }:
{
  programs.git.settings = {
    user.signingkey = lib.mkDefault "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKWqJ5X61r/CFl99qjU/rZyIB4DCQpVI+cF0y33WSSMC";
    gpg.format = lib.mkDefault "ssh";
    gpg.ssh.program = lib.mkDefault "${config.home.homeDirectory}/.agents/skills/1password/scripts/op-ssh-sign-auto";
    commit.gpgsign = lib.mkDefault true;
  };
}
