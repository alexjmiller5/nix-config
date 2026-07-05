{ pkgs, username, lib, ... }:

{
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
  ];

  programs.git = {
    enable = true;
    settings.user = {
      name = "Alex Miller";
      email = "98389659+alexjmiller5@users.noreply.github.com";
    };
  };
}
