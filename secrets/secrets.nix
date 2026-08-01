# agenix recipients. Edit/rotate a secret from the laptop with:
#   cd secrets && nix run github:ryantm/agenix -- -i ~/.ssh/agenix -e op-token.age
let
  # The Mac Mini's SSH host key — decrypts secrets at activation.
  miniHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJWXtB1aVrAYnoXQoc1R+yFAlhNK1SIfR9amzbdHqxYu";
  # Laptop on-disk key (~/.ssh/agenix, replaced blueprint_deploy_key 2026-08-01)
  # — lets Alex edit/rotate. (The 1P SSH agent can't serve age decryption,
  # hence a real on-disk key; see MANUAL.md.)
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJk1xcoSY+jfmLx5OEJH5o9i+Yr6tIvR+owFVeSqazvy";
in
{
  "op-token.age".publicKeys = [ miniHost laptop ];
}
