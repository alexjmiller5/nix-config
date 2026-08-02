{ config, ... }:

# SSH client config, split for privacy: this public module declares the
# structure (1Password agent everywhere); the actual host blocks — tailnet
# hostnames, server IPs, per-host key selectors — live in the private
# nix-secrets repo and are pulled in via Include, which ssh resolves at
# runtime. Nothing sensitive enters this repo or the nix store, and a fresh
# machine (before the private clone exists) just ignores the missing include.
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    # All private keys live in the 1Password SSH agent; the per-host
    # IdentityFile *.pub entries in the included file select among them.
    settings."*" = {
      IdentityAgent = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
    };

    includes = [
      "${config.home.homeDirectory}/Desktop/coding/active-projects/nix-secrets/ssh/hosts"
    ];
  };

  # Public-key selectors for the 1Password SSH agent — public by nature (GitHub
  # serves them at github.com/<user>.keys), so they live in this public repo
  # and a fresh machine gets them without any copying.
  home.file.".ssh/github.pub".source = ../dotfiles/ssh/github.pub;
  home.file.".ssh/mac_mini.pub".source = ../dotfiles/ssh/mac_mini.pub;
  home.file.".ssh/gcp_vm.pub".source = ../dotfiles/ssh/gcp_vm.pub;
  home.file.".ssh/claude-code-signing.pub".source = ../dotfiles/ssh/claude-code-signing.pub;
}
