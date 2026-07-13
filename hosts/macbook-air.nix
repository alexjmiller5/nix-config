# Alex's MacBook Air. Deliberately "identical to the mini for now": imports the
# mini's host config wholesale, plus noTunes. Config-only so far — NOT yet
# activated (no darwin-rebuild has run on the laptop).
#
# Before the first switch on the laptop (future task), at minimum:
#   - prune mini-only bits: never-sleep power settings, headless tailscaled
#     (laptop runs the Tailscale GUI app), screentime/callhistory backups and
#     the finance sync (those jobs live on the mini),
#   - homebrew onActivation.cleanup = "zap" will UNINSTALL every cask not
#     declared — the laptop has ~30 imperatively-installed casks; declare them
#     (or relax cleanup) first,
#   - agenix: op-token.age is encrypted to the MINI's /etc/ssh host key; add
#     the laptop's host key to secrets/secrets.nix + rekey, or drop the secret
#     (and finance sync) from this host.
{ ... }:

{
  imports = [
    ./mac-mini.nix
    ../modules/notunes.nix
  ];
}
