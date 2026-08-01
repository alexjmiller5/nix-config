{ pkgs, username, lib, ... }:

# Shared home-manager base for every host.
{
  imports = [ ./git.nix ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Access from the laptop: "Mac Mini SSH Key" in the 1Password Personal vault.
  # Written as a real file, not home.file — macOS sshd rejects an
  # authorized_keys symlinked into /nix/store.
  home.activation.installAuthorizedKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    rm -f "$HOME/.ssh/authorized_keys"
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVySz6jbVH+sW9q4+ru4CjHZjqmlMJ3p//0sLH1j8vH mac-mini' > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
  '';

  home.packages = with pkgs; [
    uv
    deno
    ripgrep
    jq
    # First brew→nixpkgs tranche (2026-08-01): pure CLI tools with no macOS
    # quirks; their brew formulae are undeclared so zap removes the dupes.
    act
    bat
    d2
    fzf
    git-filter-repo
    gitleaks
    _7zz       # brew "sevenzip"
    shellcheck
    sshpass
    tree
    yq-go      # brew "yq" is mikefarah's Go yq, matching this
  ];
}
