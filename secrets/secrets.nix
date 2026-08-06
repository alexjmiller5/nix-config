# agenix recipients — encryption needs only these PUBLIC keys, and every
# secret's source of truth is 1Password, so editing, rotating, or enrolling a
# replacement machine is recreate-not-decrypt (no master identity exists; see
# MANUAL-macbook-air.md §Fresh-machine bootstrap):
#   cd secrets && rm <name>.age
#   EDITOR=nano nix run github:ryantm/agenix -- -e <name>.age   # paste from 1P
let
  # The Mac Mini's SSH host key — decrypts mini secrets at activation.
  miniHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJWXtB1aVrAYnoXQoc1R+yFAlhNK1SIfR9amzbdHqxYu";
  # The MacBook Air's SSH host key — decrypts laptop secrets at activation.
  # Replacement laptop = new host key: swap this pubkey, recreate the laptop
  # .age files from 1P. Born on the machine, never copied anywhere.
  laptopHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlBoj7mGAPzMwmHKrxL0/5asYBViGSD4R+dxKtmmUxl";
in
{
  "op-token.age".publicKeys = [ miniHost ];
  # Fine-grained GitHub PATs for git-over-https (clone/push of the private
  # companions) — scoped to agent-config, nix-secrets, hammerspoon. Laptop:
  # Contents read/write; mini: Contents read-only (pull-only by design).
  "github-git-laptop.age".publicKeys = [ laptopHost ];
  "github-git-mini.age".publicKeys = [ miniHost ];
}
