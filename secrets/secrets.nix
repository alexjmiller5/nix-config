# agenix recipients. Edit/rotate a secret from the laptop with:
#   cd secrets && nix run github:ryantm/agenix -- -i ~/.ssh/blueprint_deploy_key -e op-token.age
let
  # The Mac Mini's SSH host key — decrypts secrets at activation.
  miniHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJWXtB1aVrAYnoXQoc1R+yFAlhNK1SIfR9amzbdHqxYu";
  # Laptop on-disk key (~/.ssh/blueprint_deploy_key) — lets Alex edit/rotate.
  # (mac_mini key lives in the 1Password SSH agent, which age can't use for decrypt.)
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIxtBDPjNRD0ZncPPXBtmFzmbvhfoEJnYZ+sm2gE5rX3";
in
{
  "op-token.age".publicKeys = [ miniHost laptop ];
}
