# nix-config

Declarative macOS machine configs via [nix-darwin](https://github.com/nix-darwin/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager).

| Host | Config |
|------|--------|
| `mac-mini` | `hosts/mac-mini.nix` (system) + `home.nix` (user) |

Day-to-day: edit config, `just switch` (on the machine) or `just switch-remote` to pull straight from GitHub. `just check` validates the flake.

## Manual setup steps (Mac Mini, from scratch)

Everything nix *cannot* do on macOS, in order. After the last step, nix does the rest.

### 1. First boot (needs a display + any mouse; no keyboard required)

1. Connect HDMI to a TV/monitor, plug in a USB mouse (or pair a Bluetooth one at the hello screen). Power button is on the **bottom** of an M4 mini.
2. On the first Setup Assistant screen, click the **Accessibility** button → **Motor** → enable the **Accessibility Keyboard**. This on-screen keyboard replaces a physical one for all of setup.
3. Prefer **ethernet** (skips typing a Wi-Fi password).
4. **Skip** Migration Assistant, Siri, Screen Time, Apple Intelligence.
5. Sign into the **Apple account** (iCloud) when prompted — doing it here beats doing it headless later. 2FA codes arrive on other trusted devices.
6. Create the local user account (username must match `username` in `flake.nix`).
7. **Decline FileVault.** A FileVaulted headless mac blocks at the pre-boot unlock screen on every reboot — no SSH until someone types the disk password locally. (Enable later only if physical access is routine.)

### 2. Enable remote access (still at the display, clicks only)

1. System Settings → General → Sharing → enable **Screen Sharing** and **Remote Login**.
2. Note the hostname shown there (e.g. `Alexanders-Mac-mini.local`).

The display, mouse, and accessibility keyboard are no longer needed — everything below runs from the laptop.

### 3. Take over from the laptop

Finder → Go → **Connect to Server** (⌘K) → `vnc://Alexanders-Mac-mini.local` → log in. Full GUI control with the laptop's keyboard.

No `ssh-copy-id` needed: the bootstrap (step 5) authenticates with the account password once, and the flake itself installs the SSH key — `home.nix` owns `authorized_keys`, key lives in 1Password ("Mac Mini SSH Key", Personal vault).

### 4. GUI-only configuration (via Screen Sharing)

1. System Settings → Apple ID → **iCloud → iCloud Drive → enable "Desktop & Documents Folders"**, and turn **off "Optimize Mac Storage"** (scripts need real files on disk, not cloud stubs).
2. System Settings → Users & Groups → enable **automatic login** (so GUI apps come up after an unattended reboot).
3. Grant any TCC prompts (Full Disk Access etc.) as they appear — macOS permission grants are GUI-only by design.

### 5. Bootstrap — one SSH command

One idempotent script installs Determinate Nix, applies the flake (Homebrew
itself via nix-homebrew, packages, dotfiles, `authorized_keys`, tailscaled,
system settings), and joins the tailnet.

Joining needs an auth key — the one irreducibly imperative bit, since Tailscale
keys cap at 90 days. Mint it from the laptop using the OAuth client in
1Password (items "Tailscale OAuth Client ID" / "Tailscale OAuth Client Secret",
Personal vault); keys minted this way **must** carry `tag:oauth-generated`:

```sh
TOKEN=$(curl -s https://api.tailscale.com/api/v2/oauth/token \
  -d "client_id=$(op item get 'Tailscale OAuth Client ID' --fields credential --reveal)" \
  -d "client_secret=$(op item get 'Tailscale OAuth Client Secret' --fields credential --reveal)" \
  | jq -r .access_token)

AUTHKEY=$(curl -s -X POST https://api.tailscale.com/api/v2/tailnet/-/keys \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true,"tags":["tag:oauth-generated"]}}},"expirySeconds":604800,"description":"mac-mini bootstrap"}' \
  | jq -r .key)
```

Then the one command (first time it authenticates with the account password;
afterwards the flake-installed key takes over). `-t` because the script sudo-prompts:

```sh
ssh -t mac-mini-local "bash <(curl -fsSL https://raw.githubusercontent.com/alexjmiller5/nix-config/main/scripts/bootstrap.sh) $AUTHKEY"
```

The tailnet hostname is pinned to `mac-mini` in the script, matching the
`mac-mini-tailscale` entry in the laptop's `~/.ssh/config`. Joining survives
reboots and rebuilds; it only recurs on a full machine rebuild.

### 6. Exit exam

Reboot the mini without touching it. Confirm `ssh mac-mini-tailscale` (from the laptop's `~/.ssh/config`) comes back on its own. If yes, unplug the display forever.
