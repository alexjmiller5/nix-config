{
  config,
  osConfig,
  lib,
  pkgs,
  shared-album-reminders,
  ...
}:

# Mini home profile: full dev parity with the laptop at the shell level —
# shared base + dev toolbox + the laptop's shell (zsh/starship/all alias
# categories) + ssh config + the agent-config fan-out so Claude Code on the
# mini gets the same skills, settings, AGENTS.md, and hooks. What stays
# laptop-only is the GUI layer (casks, dock, Chrome policy, hammerspoon,
# karabiner, VS Code) and the Apple build chain.
#
# agent-config is cloned by bootstrap-companion-repos and refreshed by the
# daily pull-only agent below. No iCloud is involved. For the agent-config
# SYNC, the laptop stays the only pusher (its sync agent commits+pushes;
# the mini's sync never writes, so there's no push race) — but the mini is
# otherwise a full dev machine: general git pushes work and auth via the
# AI Agent vault PAT (gh wrapper), same as the laptop, including daily sync.
let
  agentConfigPull = pkgs.writeShellScript "agent-config-pull" ''
    set -euo pipefail
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    cd "$HOME/.config/agent-config"
    # Claude Code rewrites claude/settings.json in place on this host (model,
    # theme) by design, and a modified tracked file aborts every ff-only pull -
    # which is how this agent sat at exit 1 for days. The laptop is
    # authoritative for that file, so drop this host's churn before pulling.
    # Memory files written here are untracked and survive; any OTHER dirty
    # tracked file still aborts on purpose (see agents.nix: mini-local memories
    # are intentional), and Vitals reports that as a red row.
    git checkout --quiet -- claude/settings.json 2>/dev/null || true
    git pull --ff-only --quiet origin main
    # PUBLIC sibling clone (generic skills reached via committed symlinks
    # in agent-config/skills) - same pull-only refresh, anonymous auth.
    cd "$HOME/.config/agent-config-public"
    git pull --ff-only --quiet origin main
    # Private ssh host blocks (programs.ssh Include): a new peer alias must
    # land here too, or ssh cannot resolve it on this machine.
    cd "$HOME/.config/nix-secrets"
    git pull --ff-only --quiet origin main
  '';
in
{
  # People Sync attaches to this machine's own shared agent Chrome.
  programs.people-sync.endpoint = "127.0.0.1:${toString osConfig.services.agent-chrome.port}";

  imports = [
    shared-album-reminders.homeModules.default
    ./common.nix
    ./agent-machine.nix
    ./agent-ssh-agent.nix
    ./ai-agent.nix
    ./claude-rc.nix
    ./dev-tools.nix
    ./apple-agent.nix
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
    ./aliases/infra.nix
    ./ssh.nix
    ./spotify-player.nix
    # Headless: no idle screen saver, so the desktop agents drive never locks.
    ./macos/screensaver.nix
    ./heartbeat.nix
  ];

  # Continuous archival runs only on the always-on mini. The laptop does not
  # run a second consumer; the app's dedicated credential lives in Keychain.
  programs.page-archiver = {
    enable = true;
    service.enable = true;
    settings = {
      hub_url = "https://life-data.nqipomyrjb.workers.dev";
      subscription_id = "1521a54f-65ac-47d1-832d-1a4d5959dd66";
      capture_table = "page_captures";
      artifact_prefix = "captures/pages/";
      max_artifact_bytes = 128 * 1024 * 1024;
      max_screenshot_pixels = 200000000;
      min_screenshot_scale = 0.5;
      retain_partial = true;
      browser_headless = false;
      credential_command = [
        "/usr/bin/security" "find-generic-password"
        "-s" "page-archiver.hub" "-a" "4947e554-dd02-4d66-9046-3cbc1a4b3a67" "-w"
      ];
    };
  };

  # Photos discovery runs only on the mini; the app owns its baseline and enrollment.
  services.shared-album-reminders.enable = true;

  # healthchecks.io check "mac-mini" (account: the primary Gmail, API key in
  # the AI Agent vault) emails when these pings stop for 5 minutes.
  services.heartbeat = {
    enable = true;
    urlFile = "${config.home.homeDirectory}/.config/nix-secrets/heartbeat/mac-mini";
  };

  # No 1P desktop app here — outbound ssh uses the default agent socket
  # (SSH_AUTH_SOCK), so a laptop agent forwarded over `ssh -A` serves the
  # keys the nix-secrets host blocks select. ssh.nix's 1P IdentityAgent
  # default would otherwise point at a socket that never exists.
  programs.ssh.settings."*".IdentityAgent = lib.mkForce "SSH_AUTH_SOCK";

  # Capability sheet this machine's agent sessions load (home/agent-machine.nix).
  agentMachine.profile = lib.mkDefault "mini";

  # Agent shells ssh to the laptop with a dedicated key held only in this
  # agent's memory (home/agent-ssh-agent.nix). Item: "AI Agent MacBook Air SSH Key".
  agentSshAgent = {
    keyOpRefs = [ "op://4eeyrkqibibn7k4j6rz2fbzvxm/2tq2nia4zgchatdagar24eyg2e/private key" ];
    tokenFile = "${config.home.homeDirectory}/.local/state/op/agent-sa-token";
  };

  # Local Connect for this machine's agent reads (home/op-connect.nix), its own
  # server and token: routine reads never touch the account SA quota.
  opConnect = {
    enable = true;
    vaultId = "4eeyrkqibibn7k4j6rz2fbzvxm";
    serverItemId = "5c5nayec7aqs6dai5l4amj725a";
    tokenOpRef = "op://4eeyrkqibibn7k4j6rz2fbzvxm/uyrwaqz6v5k7z5py7d5u7fmp2u/credential";
  };

  # The agent Chrome (hosts/mac-mini.nix services.agent-chrome) is local here:
  # chrome-control drives 127.0.0.1:9222 directly, no ssh forward.
  home.sessionVariables.CHROME_CONTROL_HOST = "local";
  # Same reach as AGENT_MACHINE: Herdr panes here are non-login shells.
  programs.zsh.envExtra = lib.mkAfter "export CHROME_CONTROL_HOST=local\n";

  # Inbound ssh from the laptop: public halves of "Mac Mini SSH Key" (Alex's
  # terminals, private half in the 1Password Personal vault) and "AI Agent
  # Mac Mini SSH Key" (laptop agent shells, private half in the AI Agent
  # vault, served by home/agent-ssh-agent.nix). Mini-only — nothing sshs
  # into the laptop. Written as a real file, not home.file — macOS sshd
  # rejects an authorized_keys symlinked into /nix/store.
  home.activation.installAuthorizedKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    rm -f "$HOME/.ssh/authorized_keys"
    {
      echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVySz6jbVH+sW9q4+ru4CjHZjqmlMJ3p//0sLH1j8vH mac-mini'
      echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKVhSzQV7atZiw0i4o51bUPL3BzzZB2DLreuQoS+/Nz0 ai-agent-mac-mini'
    } > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
  '';

  # Explicit initial cloning only (home/machine-vault-git.nix): the mini's
  # machine PAT is read-only on these repos. nix-config (public) +
  # nix-secrets make the mini self-sufficient for dev: /etc/nix-darwin
  # resolves (infra aliases), ssh host blocks resolve.
  machineVaultGit = {
    patOpRef = "op://g532a3e4zyqqrc7b2v3lhv4zmy/k55oo3omg6yvrjmj7akdjakrwm/credential";
    patAuthFile = osConfig.age.secrets.machine-sa.path;
    patRepos = [
      "alexjmiller5/agent-config"
      "alexjmiller5/nix-secrets"
    ];
    companionRepos = {
      "alexjmiller5/agent-config" = "${config.home.homeDirectory}/.config/agent-config";
      # PUBLIC sibling of agent-config (generic skills); anonymous clone/pull.
      "alexjmiller5/agent-config-public" = "${config.home.homeDirectory}/.config/agent-config-public";
      "alexjmiller5/nix-config" = "${config.home.homeDirectory}/.config/nix-config";
      "alexjmiller5/nix-secrets" = "${config.home.homeDirectory}/.config/nix-secrets";
    };
  };

  home.packages = [
    # Time-boxed Personal-vault access for agents on the headless mini. No
    # desktop app here, so Touch ID isn't an option: Alex runs `op-unlock`
    # from an ssh shell (phone terminal), types his 1Password account password,
    # and the resulting CLI session token is written to
    # ~/.local/state/op/personal-session (0600). The op-personal shell
    # function (home/zsh.nix) uses that token when the file exists, so agent
    # sessions read Personal exactly as they do on the laptop. A transient
    # launchd keepalive touches the session every 20 min (op sessions die
    # after 30 idle minutes) and after N hours (default 6) signs out
    # server-side and deletes the file. No secrets ever touch disk - only the
    # session token, which the sign-out invalidates. One-time prerequisite:
    # `op account add` on this machine (the op-account manual step below). The
    # laptop's Hammerspoon (opUnlock.lua) drives --stdin: `request` drops the
    # reason into a watched file there over ssh, the password travels back over
    # ssh stdin into a pty-driven `op signin`, and no secret is written on
    # either side.
    (pkgs.writeShellApplication {
      name = "op-unlock";
      runtimeInputs = [ pkgs._1password-cli ];
      text = ''
        state="$HOME/.local/state/op"
        f="$state/personal-session"
        case "''${1:-}" in
          keepalive) # internal: op-unlock keepalive <hours>
            end=$(( $(date +%s) + ''${2:-6} * 3600 ))
            while [ "$(date +%s)" -lt "$end" ] && [ -r "$f" ]; do
              sleep 1200
              op --session "$(cat "$f")" whoami >/dev/null 2>&1 || break
            done
            if [ -r "$f" ]; then op --session "$(cat "$f")" signout >/dev/null 2>&1 || true; fi
            rm -f "$f"
            ;;
          lock)
            /bin/launchctl remove com.alexmiller.op-unlock >/dev/null 2>&1 || true
            if [ -r "$f" ]; then
              op --session "$(cat "$f")" signout >/dev/null 2>&1 || true
              rm -f "$f"; echo "locked"
            else
              echo "already locked"
            fi
            ;;
          status)
            if [ -r "$f" ] && op --session "$(cat "$f")" whoami >/dev/null 2>&1; then
              echo "unlocked (session file $(stat -f %Sm "$f"))"
            else
              rm -f "$f"; echo "locked"
            fi
            ;;
          --stdin) # password on stdin (the laptop's Hammerspoon prompt), hours as $2
            hours="''${2:-6}"
            umask 077; mkdir -p "$state"
            /bin/launchctl remove com.alexmiller.op-unlock >/dev/null 2>&1 || true
            IFS= read -r pw || true
            if ! OP_BIN="$(command -v op)" OP_PW="$pw" /usr/bin/expect -f ${../scripts/op-signin-pty.exp} > "$f.tmp"; then
              rm -f "$f.tmp"; unset pw; exit 1
            fi
            unset pw
            mv "$f.tmp" "$f"
            /bin/launchctl submit -l com.alexmiller.op-unlock -- "$0" keepalive "$hours"
            echo "unlocked for ''${hours}h"
            ;;
          request) # ask the owner, on the laptop, to open a window
            reason=$(printf '%s' "''${2:-an agent needs a vault outside AI Agent}" | tr -c 'A-Za-z0-9 ._:/()-' ' ' | cut -c1-160)
            # A watched file, not `hs -c`: an hs client spawned from an ssh
            # session wedges Hammerspoon's IPC port (opUnlock.lua watches the dir).
            if AGENT_SHELL="''${AGENT_SHELL:-claude}" ssh -o BatchMode=yes -o ConnectTimeout=5 macbook-air-tailscale \
                "mkdir -p ~/.local/state/op-unlock && printf '%s' '$reason' > ~/.local/state/op-unlock/request" >/dev/null 2>&1; then
              echo "asked on the laptop; run op-unlock status when the vault is next needed"
            else
              echo "laptop unreachable: ask the owner to run op-unlock from their phone"
            fi
            ;;
          ""|[0-9]*)
            hours="''${1:-6}"
            umask 077; mkdir -p "$state"
            /bin/launchctl remove com.alexmiller.op-unlock >/dev/null 2>&1 || true
            # Prompts for the account password on this tty; --raw prints the token.
            env -u OP_SERVICE_ACCOUNT_TOKEN op signin --raw > "$f.tmp"
            mv "$f.tmp" "$f"
            # Transient launchd job, not screen/nohup: macOS kills those with
            # the ssh session that started them (the phone terminal closing).
            /bin/launchctl submit -l com.alexmiller.op-unlock -- "$0" keepalive "$hours"
            echo "unlocked for ''${hours}h - agents can read Personal via op-personal; op-unlock lock to end early"
            ;;
          *)
            echo "usage: op-unlock [hours=6] | --stdin [hours] | request \"<reason>\" | lock | status" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];

  # Daily pull, 30min after the laptop's 10:00 push window; RunAtLoad catches
  # up after downtime.
  launchd.agents.agent-config-pull = {
    enable = true;
    config = {
      Label = "com.alexmiller.agent-config-pull";
      # launchd has no agent shell marker; gh needs the independently enrolled
      # operator token for unattended pulls, just as the laptop sync does.
      EnvironmentVariables.AGENT_SHELL = "repo-sync";
      ProgramArguments = [ "${agentConfigPull}" ];
      RunAtLoad = true;
      StartCalendarInterval = [
        {
          Hour = 10;
          Minute = 30;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/agent-config-pull.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-config-pull.log";
    };
  };

  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  manual.steps = {
    shared-album-reminders-access = {
      title = "Shared Album Reminders Photos access and enrollment";
      owner = "shared-album-reminders";
      desktop = true;
      body = ''
        Preserve the app's XDG baseline/adoption state when replacing the machine.
        Enroll its independently minted Life credential using the installed app's
        `--enroll-token` interface from the logged-in desktop. Run the installed
        job in dry-run mode, then approve the Photos library prompt in Screen Sharing.
        macOS may identify the Nix launcher as `bash`; the permission covers the
        library although the app reads only shared-album metadata.
        Verify the launchd job `org.shared-album-reminders.daily` exits 0 and its
        log reports checked deduplication before disabling dry-run mode.
      '';
      verify = "launchctl print gui/$(id -u)/org.shared-album-reminders.daily | grep -q 'last exit code = 0'";
      redo = "on replacement machines, credential revocation, or a changed launcher identity";
    };
    people-sync-sessions = {
      title = "People Sync browser sessions";
      owner = "people-sync";
      desktop = true;
      body = ''
        Chrome owns saved social sessions. Sign in through the
        site's normal interface on a replacement machine or after session expiry.
        `people-sync-mini` supplies the local browser endpoint and state directory;
        it does not fetch credentials. For an operator run needing file capture or
        Notion, inject `~/.config/people-sync/operator.env` through desktop-auth
        `op run`, using `op-unlock` for direct mini operator access. From the laptop,
        forward only those three app values over SSH stdin, never an operator or
        CI service-account token. Life's background runner syncs local table rows
        separately using its own enrolled credential. Do not run `life sync` inside
        People Sync's file-token environment.
      '';
      redo = "after session expiry";
    };
    op-account = {
      title = "1Password CLI account (for op-unlock)";
      owner = "op-unlock";
      body = ''
        Once, over ssh, register the
        account on this machine so `op signin` works headlessly (no desktop app on
        the mini): `op account add --address my.1password.com --email <1P email>`
        - it prompts for the Secret Key and account password (password: the
        "1Password Account" item, Personal vault; Secret Key: 1Password app →
        account name in the sidebar → Manage Accounts → the account → Set Up
        Another Device, or the Emergency Kit PDF). Afterwards `op-unlock [hours]`
        from any ssh shell (phone terminal included) gives agent sessions
        time-boxed Personal-vault reads via `op-personal`; `op-unlock lock` ends
        it, `op-unlock status` checks. From an agent session here,
        `op-unlock request "<reason>"` pops the password prompt on the laptop
        (Hammerspoon `opUnlock.lua`); from a phone, run `op-unlock` in any ssh shell.
      '';
      verify = "op account list | grep -q my.1password.com";
    };
  };

}
