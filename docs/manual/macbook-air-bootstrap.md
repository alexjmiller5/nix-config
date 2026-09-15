## Bootstrap (fresh machine, in order)

Written for total loss (laptop in the ocean): nothing survives but GitHub,
1Password, and the mini. The replacement machine's SSH host key is new, so
the laptop `.age` secrets must be recreated for it BEFORE the first switch —
that's the only reason bootstrap needs a local clone instead of building
straight from the github: ref.

1. Sign in Apple ID; sign into the **App Store** (masApps installs need it).
2. Install [Determinate Nix](https://install.determinate.systems).
3. Clone this repo (public — no auth) and enroll the new machine's host key:
   ```Shell
   nix run nixpkgs#git -- clone https://github.com/alexjmiller5/nix-config ~/.config/nix-config
   cd ~/.config/nix-config
   cat /etc/ssh/ssh_host_ed25519_key.pub   # → paste over laptopHost in secrets/secrets.nix
   ```
   Then recreate the laptop's ONE secret — the `macbook-air-machine` 1P
   service-account token — for the new key (recreate-not-decrypt — no master
   key, no rekey; encryption needs only the public keys in secrets.nix). Read
   the token from the 1Password **web vault** (1password.com in Safari — the
   1P app isn't installed until the first switch; the SA token item lives in
   the "MacBook Air" vault). Agent operator credentials have their own
   enrollment below; this machine token does not supply them:
   ```Shell
   cd secrets && rm machine-sa-laptop.age
   EDITOR=nano nix run github:ryantm/agenix -- -e machine-sa-laptop.age   # paste SA token from 1P web
   cd .. && nix run nixpkgs#git -- add -A   # flakes only see tracked files
   ```
4. First switch, from the local tree:
   ```Shell
   nix build .#darwinConfigurations.macbook-air.system
   sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-air
   ```
   Activation decrypts the bootstrap token onto the agenix RAM disk and
   installs `bootstrap-companion-repos`. `/etc/nix-darwin` links to the clone;
   the `switch-laptop` alias works from anywhere. Activation never reads the
   machine vault or clones companions.
5. Sign into the 1Password app (installed by the switch); `op signin`. There
   is no `gh auth login` or `op plugin` setup: ongoing Git auth uses the
   operator `gh` PATH wrapper.
6. Home Manager creates plugin links inside `~/.config/agent-config` before
   the first clone. If this directory has no `.git`, preserve it elsewhere
   first (choose an unused backup destination):
   ```Shell
   mv ~/.config/agent-config ~/.config/agent-config.bootstrap-links
   ```
   Then run the explicit initial clone command as the user in that terminal:
   ```Shell
   bootstrap-companion-repos
   ```
   It skips existing clones and refuses non-repository directories without
   reading credentials. Only missing repos in `patRepos` get a
   machine-vault helper passed to that single `git clone` command; nothing
   is saved in Git config. Other clones, including hammerspoon, use normal
   Git auth. Failure stops the command; correct bootstrap access and rerun
   it to finish initial setup. Run `switch-laptop` again to restore declared
   plugin links into the clone; the out-of-store symlinks then resolve.
   Later switches never retry bootstrap. To recover a deleted clone on an
   enrolled machine, use ordinary `git clone` with operator auth.
   Enroll the independent AI Agent token below for unattended repo sync.
7. Commit + push the step-3 changes (secrets.nix + the recreated .age) — push
   auth works now.
8. Trust the third-party taps (brew's tap-trust gate blocks formula loads
   otherwise): `for t in alexjmiller5/tap steipete/tap; do brew trust "$t"; done`
