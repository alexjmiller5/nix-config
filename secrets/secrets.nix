# agenix recipients — mini-only. No laptop key exists: encryption needs only
# these PUBLIC keys, and the secret's source of truth is 1Password, so
# editing/rotating from the laptop is recreate-not-decrypt (see MANUAL-macbook-air.md):
#   cd secrets && rm op-token.age
#   EDITOR=nano nix run github:ryantm/agenix -- -e op-token.age   # paste from 1P
let
  # The Mac Mini's SSH host key — decrypts secrets at activation.
  miniHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJWXtB1aVrAYnoXQoc1R+yFAlhNK1SIfR9amzbdHqxYu";
in
{
  "op-token.age".publicKeys = [ miniHost ];
}
