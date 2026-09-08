# MANUAL-mac-mini.md — headless Mini steps nix cannot do

Everything nix *cannot* do on macOS, in order. After the last step, nix does the rest.

### 1. First boot (needs a display + any mouse; no keyboard required)

1. Connect HDMI to a TV/monitor, plug in a USB mouse (or pair a Bluetooth one at the hello screen). Power button is on the **bottom** of an M4 mini.
2. On the first Setup Assistant screen, click the **Accessibility** button → **Motor** → enable the **Accessibility Keyboard**. This on-screen keyboard replaces a physical one for all of setup.
3. Prefer **ethernet** (skips typing a Wi-Fi password).
4. **Skip** Migration Assistant, Siri, Screen Time, Apple Intelligence.
5. **Skip Apple account sign-in during Setup Assistant.** Signing in here silently enables FileVault (no prompt, key escrowed to iCloud) — see below for why that's fatal. Sign into iCloud later via System Settings, which does NOT auto-enable FileVault.
6. Create the local user account (username must match `username` in `flake.nix`).
7. **Decline FileVault**, and after first login verify with `fdesetup status` (disable with `sudo fdesetup disable`; don't reboot until decryption completes). A FileVaulted headless mac blocks at the **pre-boot unlock screen** on every reboot — no SSH, no network, and the pre-boot screen has NO accessibility keyboard, so a mouse-only setup is bricked until a physical keyboard is found. Learned the hard way.

### 2. Enable remote access (still at the display, clicks only)

1. System Settings → General → Sharing → enable **Screen Sharing** and **Remote Login**.
2. Note the hostname shown there (e.g. `Alexanders-Mac-mini.local`).

The display, mouse, and accessibility keyboard are no longer needed — everything below runs from the laptop.

### 3. Take over from the laptop

Finder → Go → **Connect to Server** (⌘K) → `vnc://Alexanders-Mac-mini.local` → log in. Full GUI control with the laptop's keyboard.

No `ssh-copy-id` needed: the bootstrap (step 5) authenticates with the account password once, and the flake itself installs the SSH key — `home.nix` owns `authorized_keys`, key lives in 1Password ("Mac Mini SSH Key", Personal vault).

### 4. GUI-only configuration (via Screen Sharing)

1. *(Optional — only for replicating the weekly backup output off the mini.)* Nothing on the mini **reads** from iCloud anymore (agent-config arrives via git, see §6), but screentime/callhistory snapshots **write** to `~/Documents`; to have iCloud carry those off-machine: System Settings → Apple ID → **iCloud → iCloud Drive → enable "Desktop & Documents Folders"** with **"Optimize Mac Storage" on** (the full mirror outgrew the mini's 228GB disk — it hit 0 bytes free with Optimize off).
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

```Shell
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

```Shell
ssh -t mac-mini-local "bash <(curl -fsSL https://raw.githubusercontent.com/alexjmiller5/nix-config/main/scripts/bootstrap.sh) $AUTHKEY"
```

The tailnet hostname is pinned to `mac-mini` in the script, matching the
`mac-mini-tailscale` entry in the laptop's `~/.ssh/config`. Joining survives
reboots and rebuilds; it only recurs on a full machine rebuild.

The script also advertises the machine as an **exit node** (a runtime
tailscaled preference, persisted across reboots — nix-darwin has no module
option for it). Exit nodes need approval; keep this `autoApprovers` rule in
the tailnet ACL so tagged devices are approved automatically:

```jsonc
"autoApprovers": { "exitNode": ["tag:oauth-generated"] }
```

### 6. Per-module manual steps (TCC — GUI-only by design)

* **agent-config (Claude skills/settings fan-out)**: no login — the clone +
  daily pull authenticate via the machine-vault git credential helper
  (agenix `machine-sa-mini` → `op read` of the read-only PAT). If the mini is
  rebuilt from scratch its host key is new: recreate `machine-sa-mini.age`
  (recreate-not-decrypt, commands in `secrets/secrets.nix` header, token from
  the 1P "Mac Mini" vault) BEFORE the first deploy, then `just deploy` again
  so activation clones `~/.config/agent-config` and the symlinks resolve.
* **screentime-backup** + **callhistory-backup** (weekly Apple-data snapshots):
  grant Full Disk Access once per app — System Settings → Privacy & Security →
  **Full Disk Access** → **\[+]** → `/Applications/ScreenTimeBackup.app` and
  `/Applications/CallHistoryBackup.app`, toggle on. Each app is re-signed with
  its same stable cert every rebuild, so the grants persist. Verify:
  `launchctl kickstart -k gui/$(id -u)/com.alexmiller.screentime-backup` (and
  `...callhistory-backup`), then check `~/Library/Logs/<name>.log` for
  `backup OK` lines (a `cannot read` line means the grant is missing).
* **See + click the screen from ssh (agents)**: every ssh-spawned process is
  attributed by TCC to `/usr/libexec/sshd-keygen-wrapper`, so grant that ONE
  binary, via Screen Sharing: System Settings → Privacy & Security →
  **Screen Recording** → \[+] → ⌘⇧G → `/usr/libexec/sshd-keygen-wrapper`,
  toggle on; same under **Accessibility**. Then from an ssh shell run
  `osascript -e 'tell application "System Events" to get name of every process'`
  once and click **Allow** on the "sshd-keygen-wrapper wants to control
  System Events" dialog that appears on the mini's display. Verify:
  `screencapture -x /tmp/s.png && file /tmp/s.png` (a real PNG, not black)
  and `osascript -e 'tell application "System Events" to click at {10, 10}'`
  (no -1719/-1743 error). After this, agents screenshot with
  `screencapture`, click/type with System Events, and can dismiss later
  dialogs themselves; only these grants and anything asking for the admin
  password stay human.
* **moshi-hook (Moshi phone-terminal agent daemon)**: the brew formula, its
  launchd service, and the Claude Code hooks (agent-config
  `claude/settings.json`) are all declared; the pairing state is restored at
  login from the 1P item "Mac Mini Moshi Host Secret" (`home/moshi-hook.nix`).
  Pairing itself is a one-time secret handshake you do over ssh, only when the
  1P item does not exist yet (first setup, or after un-pairing the host in the
  app): Moshi app → Settings → Hooks → copy the token, then
  `moshi-hook pair --store file --token <token>` (`--store file`: the login
  Keychain is locked for ssh shells), then put the resulting
  `~/.config/moshi/secrets.json` and `config.json` contents into that item's
  `secrets_json` / `config_json` fields (an agent does this with one
  desktop-auth `op item create`). Never run `moshi-hook install` here -
  `~/.claude/settings.json` is a read-only nix symlink; the hooks it would
  write are already in agent-config.
* **1Password CLI account (for `op-unlock`)**: once, over ssh, register the
  account on this machine so `op signin` works headlessly (no desktop app on
  the mini): `op account add --address my.1password.com --email <1P email>`
  — it prompts for the Secret Key and account password (password: the
  "1Password Account" item, Personal vault; Secret Key: 1Password app →
  account name in the sidebar → Manage Accounts → the account → Set Up
  Another Device, or the Emergency Kit PDF). Afterwards `op-unlock [hours]`
  from any ssh shell (phone terminal included) gives agent sessions
  time-boxed Personal-vault reads via `op-personal`; `op-unlock lock` ends
  it, `op-unlock status` checks.
* **Messages (SMS 2FA codes reach agents)**: via Screen Sharing sign Messages
  into iMessage, then on the iPhone Settings → Messages → **Text Message
  Forwarding** → enable this mini. Verify with
  `sqlite3 ~/Library/Messages/chat.db "select count(*) from message where service='SMS'"`
  (non-zero = forwarding works; `imsg`/sqlite readers need Full Disk Access).
* **whatsapp (companion device for callhistory-backup)**: via Screen Sharing,
  open WhatsApp once → Settings on the iPhone → Linked Devices → Link a Device
  → scan the QR on the mini's screen. The keep-alive agent keeps it running
  afterward; no re-linking needed as long as the phone comes online every
  14 days and the app keeps running.

### 7. Exit exam

Reboot the mini without touching it. Confirm `ssh mac-mini-tailscale` (from the laptop's `~/.ssh/config`) comes back on its own. If yes, unplug the display forever.
