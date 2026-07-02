{ pkgs, username, ... }:

{
  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Access from the laptop: "Mac Mini SSH Key" in the 1Password Personal vault.
  home.file.".ssh/authorized_keys".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVySz6jbVH+sW9q4+ru4CjHZjqmlMJ3p//0sLH1j8vH mac-mini
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
