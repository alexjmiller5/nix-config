# agenix recipients — encryption needs only these PUBLIC keys, and every
# secret's source of truth is 1Password, so editing, rotating, or enrolling a
# replacement machine is recreate-not-decrypt (no master identity exists; see
# MANUAL-macbook-air.md §Fresh-machine bootstrap):
#   cd secrets && rm <name>.age
#   EDITOR=nano nix run github:ryantm/agenix -- -e <name>.age   # paste from 1P
#
# Design: agenix holds exactly ONE secret per machine — that machine's 1P
# service-account token (read-only on its machine vault). Everything else
# (git PATs, the finance SA token, future secrets) lives in the machine vault
# and is fetched at runtime via `op read`, so new/rotated secrets never touch
# this repo.
let
  # The Mac Mini's SSH host key — decrypts mini secrets at activation.
  miniHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJWXtB1aVrAYnoXQoc1R+yFAlhNK1SIfR9amzbdHqxYu";
  # The MacBook Air's SSH host key — decrypts laptop secrets at activation.
  # Replacement laptop = new host key: swap this pubkey, recreate the laptop
  # .age file from 1P. Born on the machine, never copied anywhere.
  laptopHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlBoj7mGAPzMwmHKrxL0/5asYBViGSD4R+dxKtmmUxl";
in
{
  # 1P service-account tokens, one per machine ("macbook-air-machine" /
  # "mac-mini-machine" SAs, read-only on the "MacBook Air" / "Mac Mini" vaults).
  "machine-sa-laptop.age".publicKeys = [ laptopHost ];
  "machine-sa-mini.age".publicKeys = [ miniHost ];

  # LEGACY — finance-project SA token, decrypted for notion-finance-sync.
  # Removed once the sync fetches it from the Mac Mini machine vault at run
  # time (op read via machine-sa-mini).
  "op-token.age".publicKeys = [ miniHost ];
}
