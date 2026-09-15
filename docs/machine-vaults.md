# Machine vaults (1P) - the secret architecture

Each machine has a 1P vault ("MacBook Air" / "Mac Mini") and a read-only
service account (`macbook-air-machine` / `mac-mini-machine`). agenix encrypts
exactly ONE secret per machine - its bootstrap SA token. Machine vaults are
for initial Nix bootstrap; agent operator credentials use the independent
enrollment above. Each host's `machineVaultGit.patOpRef` identifies its
fine-grained bootstrap GitHub PAT. `patRepos` limits the helper to initial
clones of the listed repositories; it must stay within the PAT's grants.
Cloning needs Contents read access only, regardless of any broader existing
PAT grant. No routine pull or push uses these PATs. Both hosts' launchd repo
sync jobs use the operator `gh` helper with the independently enrolled AI
Agent token; they do not read or refresh machine-vault credentials.

PATs are minted by hand (GitHub has no token-creation API): github.com →
Settings → Developer settings → Fine-grained tokens; they cap at 1-year
expiry, so ensure the bootstrap PAT is valid before setting up a replacement
machine. Its expiry does not affect daily repo sync. Machine lost = revoke
that machine's SA (1P dashboard), drop its
pubkey from secrets.nix, recreate its .age; the vault contents rotate at
leisure since the SA token was the only thing the disk could yield.
